import UIKit

final class ContextMenuMorphHostView: UIView {
    // MARK: - Configuration

    struct Metrics: Equatable {
        let collapsedFrame: CGRect
        let collapsedCornerRadius: CGFloat
        let expandedFrame: CGRect
        let expandedCornerRadius: CGFloat
    }

    // MARK: - Subviews

    let glass: MenuGlassSurfaceView
    let sourceContent = UIView()
    let destinationContent = UIView()

    /// Passthrough wrapper between the morph host and the glass view.
    /// Exists so `LensSDFFilter` can install on a plain-UIView layer
    /// whose composited output includes BOTH the glass backdrop blur
    /// AND the content inside — when the filter lives on the
    /// `UIVisualEffectView`'s own layer, its private backdrop layer
    /// bypasses the `filters` chain and only the content rows get the
    /// refraction, leaving the pill itself static during the morph.
    ///
    /// Tracks `bounds` exactly; no anchor/mask/transform of its own, so
    /// the SDF sample origin stays aligned with the morph geometry.
    let lensContainer = UIView()

    // MARK: - State

    private(set) var metrics: Metrics?

    var progress: CGFloat {
        get { progressValue }
        set {
            cancelDisplayLink()
            progressValue = newValue
            phaseValue = max(0, min(1, newValue))
            updateForProgress(surfaceProgress: newValue, phaseProgress: phaseValue)
        }
    }

    // MARK: - Private state

    private var progressValue: CGFloat = 0
    private var phaseValue: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var animStart: CFTimeInterval = 0
    private var animDuration: TimeInterval = 0
    private var animFrom: CGFloat = 0
    private var animTo: CGFloat = 0
    private var animDamping: CGFloat = 0.898
    private var animStep: ((CGFloat) -> Void)?
    private var animCompletion: ((Bool) -> Void)?

    /// When `true`, the droplet deformation (`blob` + `topDome`) is
    /// suppressed — the host stays a lerping rounded rectangle. Used
    /// by the dismiss path to collapse the menu back to the source
    /// rect as a plain geometric shrink, letting the cross-fade
    /// between menu rows and source snapshot read cleanly without a
    /// droplet silhouette flashing through.
    var suppressBlob: Bool = false

    private static let collapsedShadowRadius: CGFloat = 12.0
    private static let expandedShadowRadius: CGFloat = 20.0
    // At t=0 the shadow is invisible. The ramp (see
    // `updateForProgress`) holds 0 through ALMOST the entire morph
    // and only smoothsteps on in the last ~25 %, at reduced
    // amplitude. Matches iOS 26 context menus where the landed menu
    // has only a faint shadow and no shadow shows during the
    // unfold.
    private static let collapsedShadowOpacity: Float = 0.0
    private static let expandedShadowOpacity: Float = 0.08
    private static let shadowOffset = CGSize(width: 0, height: 4)

    // MARK: - Init

    init(isDark: Bool) {
        self.glass = MenuGlassSurfaceView(isDark: isDark)
        super.init(frame: .zero)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = Self.shadowOffset
        layer.shadowRadius = Self.collapsedShadowRadius
        layer.shadowOpacity = Self.collapsedShadowOpacity

        glass.clipsToBounds = false
        if #available(iOS 13.0, *) {
            glass.layer.cornerCurve = .continuous
        }

        // No layer.mask — glass clips itself via cornerRadius +
        // masksToBounds. A CAShapeLayer mask on the host re-
        // rasterised the entire layer on every CADisplayLink tick
        // (60 / 120 frames per second of expensive raster work),
        // which manifested as visible "missing-frame" stutter
        // during the morph.

        lensContainer.backgroundColor = .clear
        lensContainer.clipsToBounds = false
        addSubview(lensContainer)
        lensContainer.addSubview(glass)

        sourceContent.backgroundColor = .clear
        sourceContent.isUserInteractionEnabled = false
        glass.contentView.addSubview(sourceContent)

        destinationContent.backgroundColor = .clear
        destinationContent.isUserInteractionEnabled = true
        glass.contentView.addSubview(destinationContent)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Configuration

    private var xAnchor: CGFloat = 0.5
    private var yAnchor: CGFloat = 0.0

    func configure(metrics: Metrics) {
        self.metrics = metrics

        // Force horizontal center-anchor for the morph. Edge-match
        // detection (droplet.maxX ≈ menu.maxX or droplet.minX ≈
        // menu.minX) would pick a left or right anchor, making the
        // morph read as "unfolds from one edge" — which is exactly
        // what the user flagged. With center-anchor the bubble scales
        // bilaterally from its midpoint regardless of whether the
        // menu is centered, left-aligned, or right-aligned with the
        // source. Any horizontal mismatch between droplet.midX and
        // menu.midX is absorbed as a smooth position lerp.
        xAnchor = 0.5

        let tolerance: CGFloat = 1.0
        if abs(metrics.expandedFrame.minY - metrics.collapsedFrame.minY) <= tolerance {
            yAnchor = 0.0
        } else if abs(metrics.expandedFrame.maxY - metrics.collapsedFrame.maxY) <= tolerance {
            yAnchor = 1.0
        } else {
            yAnchor = 0.5
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer.anchorPoint = CGPoint(x: xAnchor, y: yAnchor)

        sourceContent.frame = CGRect(origin: .zero, size: metrics.collapsedFrame.size)
        destinationContent.frame = CGRect(origin: .zero, size: metrics.expandedFrame.size)

        updateForProgress(surfaceProgress: progressValue, phaseProgress: phaseValue)

        CATransaction.commit()
    }

    // MARK: - Animation API

    func animateProgress(
        to target: CGFloat,
        duration: TimeInterval,
        damping: CGFloat = 0.78,
        step: ((CGFloat) -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let previousCompletion = animCompletion
        cancelDisplayLink()
        previousCompletion?(false)

        animStart = CACurrentMediaTime()
        animDuration = duration
        animFrom = progressValue
        animTo = target
        animDamping = damping
        animStep = step
        animCompletion = completion

        step?(progressValue)

        if duration <= 0 {
            progressValue = target
            phaseValue = max(0, min(1, target))
            updateForProgress(surfaceProgress: target, phaseProgress: phaseValue)
            step?(target)
            let c = animCompletion
            animCompletion = nil
            c?(true)
            return
        }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        // Opt into ProMotion 120 Hz on supported devices. Without this,
        // CADisplayLink defaults to 60 Hz even on 120 Hz displays,
        // which shows as subtle stairstepping in the shape-path updates
        // during fast morphs.
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 80,
                maximum: 120,
                preferred: 120
            )
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancelAnimation() {
        cancelDisplayLink()
    }

    private func cancelDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        animStep = nil
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - animStart
        let tRaw = CGFloat(elapsed / animDuration)
        let tClamped = max(0, min(1, tRaw))

        let eased = Self.springProgress(tClamped, damping: animDamping)
        let value = animFrom + (animTo - animFrom) * eased

        let phaseFrom = max(0, min(1, animFrom))
        let phaseTo = max(0, min(1, animTo))
        let phase = phaseFrom + (phaseTo - phaseFrom) * tClamped

        progressValue = value
        phaseValue = phase
        updateForProgress(surfaceProgress: value, phaseProgress: phase, rawTime: tClamped)
        animStep?(value)

        if tRaw >= 1 {
            link.invalidate()
            displayLink = nil
            let c = animCompletion
            animCompletion = nil
            animStep = nil
            c?(true)
        }
    }

    // MARK: - Progress → visuals

    private func updateForProgress(surfaceProgress: CGFloat, phaseProgress: CGFloat, rawTime: CGFloat = 0) {
        guard let metrics else { return }

        let gt = max(0, min(1, surfaceProgress))
        let phaseT = max(0, min(1, phaseProgress))

        // Position and size curves ride `gt` (cubic-ease-out),
        // both running over the FULL timeline now. The previous
        // version saturated position at `gt=0.4` and started size
        // at `gt=0.15`, which under the new ease-out curve meant
        // position arrived at τ≈0.13 and the host then sat with
        // a fixed centre while size finished expanding — perceived
        // as "travel, plateau, then inflate".
        //
        // Mapping both ranges to `[0, 1]` lets position and size
        // share one velocity profile: the bubble travels TOWARD
        // menu.mid at the same rate it grows, so position and
        // size resolve simultaneously at τ=1. Each is wrapped in
        // `smootherstep` so the second derivative is zero at the
        // endpoints — no kink at start/finish.
        let positionT = Self.smootherstep(0, 1, gt)
        let sizeT = Self.smootherstep(0, 1, gt)

        let midX = Self.lerp(metrics.collapsedFrame.midX, metrics.expandedFrame.midX, positionT)
        let midY = Self.lerp(metrics.collapsedFrame.midY, metrics.expandedFrame.midY, positionT)
        let width = Self.lerp(metrics.collapsedFrame.width, metrics.expandedFrame.width, sizeT)
        let height = Self.lerp(metrics.collapsedFrame.height, metrics.expandedFrame.height, sizeT)
        let lerpFrame = CGRect(
            x: midX - width / 2,
            y: midY - height / 2,
            width: width,
            height: height
        )
        // Pill-biased corner: in the early/middle morph the corner
        // is biased toward `min(w, h) / 2` (full pill), which makes
        // the interim shape read as a fat capsule instead of a
        // softly-rounded rectangle. Bias relaxes to the menu's
        // final cornerRadius over a wide `gt ∈ [0.4, 1.0]` window
        // through smootherstep, so the transition is C²-continuous
        // and never "snaps". The previous attempt that gated the
        // bias to `[0.75, 1.0]` produced the visible "финальный
        // разворот" jerk because the shape changed too late and
        // too fast — by spreading the relaxation over 60 % of the
        // timeline, the corner glides toward the menu radius
        // imperceptibly.
        //
        // At `gt = 0` the formula yields `collapsedCornerRadius`
        // exactly (pillBias=1 + pillCorner=collapsedRadius for
        // the droplet), so the start state matches the droplet's
        // geometry without a discontinuity.
        let pillCorner = min(width, height) / 2
        let menuCorner = metrics.expandedCornerRadius
        let pillBias = 1 - Self.smootherstep(0.4, 1.0, gt)
        let baseCorner = menuCorner + (pillCorner - menuCorner) * pillBias

        // Droplet silhouette suppressed on open too (previously only
        // on dismiss). The user wanted a rounder, cleaner morph;
        // the teardrop bulge reads as teardrop tension which is at
        // odds with the "bubble inflates into menu" feel.
        let blob: CGFloat = 0
        let topDome: CGFloat = 0
        _ = Self.blobAmount(for: phaseT)
        _ = Self.topDomeAmount(for: phaseT, hostHeight: lerpFrame.height)

        // Не схлопываем host слишком сильно — иначе форма выглядит как
        // умирающий мешочек. Только лёгкое сужение и небольшое удлинение.
        let widthInset = blob * min(18, lerpFrame.width * 0.08)
        let heightStretch = blob * min(22, lerpFrame.height * 0.08)

        let bulgedFrame = CGRect(
            x: lerpFrame.minX + widthInset * xAnchor,
            y: lerpFrame.minY - topDome - heightStretch * 0.35,
            width: lerpFrame.width - widthInset,
            height: lerpFrame.height + topDome + heightStretch
        )

        let cornerPulse = blob * min(baseCorner * 0.18, 8)
        let cornerRadius = baseCorner + cornerPulse

        let shadowRadius = Self.lerp(Self.collapsedShadowRadius, Self.expandedShadowRadius, gt)
        // Shadow ramps ONLY in the last ~25 % of the morph. Before
        // that the value is 0 so the growing droplet casts no drop-
        // shadow — a shadow during the bulge phase reads as "menu is
        // already settled" and fights the unfold. Keyed off
        // `phaseT` (not the spring `gt`) so the ramp doesn't
        // overshoot on open nor undershoot on dismiss.
        // Shadow ramp window widened from 0.75–1.0 to 0.5–1.0 so
        // the drop-shadow fades in over the entire back half of
        // the morph instead of "popping" on at τ=0.75. Quintic
        // smootherstep means the very start of the ramp is
        // imperceptible; the shadow only becomes visibly present
        // once the menu shape has substantially landed.
        let shadowRampT = Self.smootherstep(0.5, 1.0, phaseT)
        let shadowOpacity = Float(
            Self.lerp(
                CGFloat(Self.collapsedShadowOpacity),
                CGFloat(Self.expandedShadowOpacity),
                shadowRampT
            )
        )

        // Параллельная хореография: всё идёт за одну и ту же полную
        // длительность [0, 1]. Source смотрим как он уходит, dest —
        // как приходит, blob — bell. Никто не стартует с задержкой
        // и не финиширует раньше — это то, что даёт "одна цельная
        // трансформация" вместо "череды микро-анимаций с плато".
        let sourceFadeOut = Self.smootherstep(0.0, 1.0, phaseT)
        let sourceAlpha = max(0, 1 - sourceFadeOut)
        let sourceScale = 1.0 - 0.08 * sourceFadeOut

        let destFadeIn = Self.smootherstep(0.0, 1.0, phaseT)
        let destAlpha = destFadeIn
        // No translateY — content stays put, just fades in. The
        // previous 8 pt slide was too subtle to register as "menu
        // rows dropping into place" and instead created a vertical
        // nudge that muddied the clean bilateral growth.
        let destTranslateY: CGFloat = 0

        // End-bounce — raised-cosine bump `(1 - cos(2π·s)) / 2` over
        // `phaseT ∈ [0.35, 0.85]`. Window centred on `τ=0.6`, where
        // the cubic-ease-out has resolved ~94 % of the size lerp,
        // so the bump reads as the "landing" rather than a
        // separate animation that fires after the menu has already
        // stopped. The previous (0.5, 1.0) window peaked at τ=0.75,
        // by which point movement was visibly already done — the
        // bump felt detached / late.
        //
        // Raised-cosine has zero derivative at BOTH endpoints AND
        // at the peak — no kink at engage / disengage / crest. A
        // half-sine `sin(π·s)` would click on engage and disengage
        // (non-zero slope at s=0 and s=1), which is what made the
        // earlier "spring" read as harsh on a 120 Hz display.
        let bouncePhase = max(0, min(1, (phaseT - 0.35) / 0.5))
        let bounceAmplitude: CGFloat = 0.025
        let bounceScale = 1 + bounceAmplitude * (1 - cos(bouncePhase * 2 * .pi)) / 2

        // Start-pop — half-sine `sin(π·s)` over the first 28 % of
        // raw time. Two components: scale-up by 14 % AND vertical
        // translate up by 28 pt (open only). The window stretched
        // from 22 % → 28 % so the pop has more time to read on a
        // 0.5 s morph, and amplitudes both roughly doubled because
        // the previous values were getting visually swallowed —
        // the bubble starts at 24 pt, a 9 % scale was changing its
        // size by only 2 pt (sub-pixel-noise-level on Retina),
        // and a 14 pt translate was about half a finger-width.
        // 28 pt translate is roughly the bubble's own diameter,
        // so the pop reads as the bubble visibly "jumping" up
        // its own height before settling.
        //
        // On dismiss the translate is suppressed — a downward
        // jolt at the start of close reads as a glitch. Scale
        // pop still fires symmetrically. Open detection:
        // `animTo > animFrom`.
        let isOpening = animTo > animFrom
        let startBumpT = max(0, min(1, rawTime / 0.28))
        let startBumpEnv = sin(startBumpT * .pi)
        let startBumpAmplitude: CGFloat = 0.14
        let startBumpScale = 1 + startBumpAmplitude * startBumpEnv
        let startBumpTranslateY: CGFloat = isOpening ? -28 * startBumpEnv : 0

        let springScaleX = bounceScale * startBumpScale
        let springScaleY = bounceScale * startBumpScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let anchorPositionX = bulgedFrame.minX + bulgedFrame.width * xAnchor
        let anchorPositionY = bulgedFrame.minY + bulgedFrame.height * yAnchor

        bounds = CGRect(origin: .zero, size: bulgedFrame.size)
        layer.position = CGPoint(x: anchorPositionX, y: anchorPositionY)
        transform = CGAffineTransform(scaleX: springScaleX, y: springScaleY)
            .concatenating(CGAffineTransform(translationX: 0, y: startBumpTranslateY))

        // `glass` MUST be sized via `view.frame` (not `layer.frame`).
        // `UIVisualEffectView` owns a private `_UIVisualEffectBackdropView`
        // child that gets re-laid-out only inside the public
        // `layoutSubviews` pipeline; setting `glass.layer.frame`
        // skips that pipeline entirely, so the backdrop view stays
        // at its previous size and the glass effect visibly
        // disappears (the container's bounds change but the
        // effect surface doesn't follow).
        //
        // `lensContainer` is a plain `UIView` with no UIKit-managed
        // subviews — only the SDF filter chain on its layer — so
        // `layer.frame` direct-set is fine and skips one
        // layoutSubviews schedule per tick.
        glass.frame = bounds
        lensContainer.layer.frame = bounds

        // Glass clips itself via its own cornerRadius (the
        // `UIGlassEffect` backdrop on iOS 26 honors the layer's
        // rounded-rect clip natively). lensContainer carries the
        // same cornerRadius for SDF lens alignment but doesn't
        // clip — its layer hosts the displacement filter chain
        // that needs to extend beyond the rounded rect for the
        // "lens" refraction at the edges.
        glass.layer.cornerRadius = cornerRadius
        glass.layer.masksToBounds = true
        lensContainer.layer.cornerRadius = cornerRadius

        // CGPath direct constructor instead of `UIBezierPath`
        // wrapper — avoids the Obj-C bridging round-trip and the
        // intermediate `UIBezierPath` instance allocation. At
        // 120 Hz with the wrapper, this was a measurable share of
        // per-tick allocator pressure.
        let shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: bulgedFrame.size),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        layer.shadowPath = shadowPath
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity

        // sourceContent is intentionally empty in the morph
        // setup (the controller does NOT embed a snapshot — the
        // real source view stays put in its parent). So updating
        // its frame/alpha/transform per tick is wasted work
        // (sourceAlpha, sourceScale calculated above are unused).
        // destinationContent only needs frame on bounds change;
        // the (translateY=0) transform never changes, so it's
        // set once and left alone.
        _ = sourceAlpha
        _ = sourceScale
        _ = destTranslateY
        let destLocalOrigin = CGPoint(
            x: metrics.expandedFrame.minX - bulgedFrame.minX,
            y: metrics.expandedFrame.minY - bulgedFrame.minY
        )
        destinationContent.layer.frame = CGRect(origin: destLocalOrigin, size: metrics.expandedFrame.size)
        destinationContent.alpha = destAlpha

        CATransaction.commit()
    }

    // MARK: - Shape

    private static func makeMorphPath(
        in rect: CGRect,
        cornerRadius: CGFloat,
        blob: CGFloat,
        xAnchor: CGFloat,
        topDome: CGFloat
    ) -> CGPath {
        guard rect.width > 0, rect.height > 0 else {
            return UIBezierPath(rect: rect).cgPath
        }

        let t = max(0, min(blob, 1))

        // Только истинный ноль — плоский rounded rect. Для любого t > 0
        // формулы ниже сконструированы так, что при t → 0 путь плавно
        // сходится к rounded rect: точек излома нет.
        if t <= 0 {
            return UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
        }

        let w = rect.width
        let h = rect.height
        let midX = rect.midX

        // Центр массы слегка уходит к якорю, но не слишком,
        // чтобы форма не казалась косой.
        let anchorBias = (xAnchor - 0.5) * w * 0.12 * t

        // Узкая шейка. Это один из главных признаков капли.
        // При t=0 шейка во всю ширину (= верхний край rect). При t=1 узкая (30% w).
        // Раньше была max(16, w * (0.48 - 0.18*t)) — при t→0 шейка давала ≈48% ширины,
        // что визуально отличалось от rounded rect и давало скачок в момент схлопа
        // blob'а. Теперь на всём интервале плавно сходится к полной ширине.
        let neckWidth = w - (w - max(16, w * 0.30)) * t
        let neckHalf = neckWidth * 0.5

        // Верхний пик — уже был t-параметризован через topDome (= 0 при t=0).
        let apexLift = min(h * 0.18, topDome + h * 0.04 * t)

        // Уровень шейки. При t=0 лежит на верхнем крае rect (topDome=0, floor убран).
        let neckY = rect.minY + topDome * (0.78 + 0.18 * t)

        // Плечи и пузо теперь t-параметризованы: при t=0 схлопываются к
        // границам rect (плечо = верх, пузо = низ), что даёт ровные боковые
        // стороны без "раздувания".
        let shoulderY = rect.minY + h * (0.12 + 0.15 * t)
        let bellyY = rect.maxY - h * (0.40 - 0.05 * t) * t

        // Ширина тела. При t=0 inset = 0 (пузо во всю ширину). При t=1 ≈ 3.5% w.
        // Убран floor max(4, ...) — он не давал пузу сойтись с rect-краями.
        let bellyInset = w * 0.035 * t
        let leftBellyX = rect.minX + bellyInset + anchorBias * 0.25
        let rightBellyX = rect.maxX - bellyInset + anchorBias * 0.25

        // Низ. При t=0 bottomY = maxY (плоский низ без смещения).
        let bottomY = rect.maxY - h * 0.03 * t
        let bottomMidX = rect.midX + anchorBias * 0.55

        let neckLeftX = midX - neckHalf + anchorBias
        let neckRightX = midX + neckHalf + anchorBias
        let apexX = midX + anchorBias
        // Апекс почти прилегает к `rect.minY` — купол выглядит как
        // круглая шапка, а не заострённая капля. apexCpY на той же
        // высоте → горизонтальная касательная в вершине.
        let apexY = rect.minY - apexLift * 0.04
        let apexCpY = apexY
        // cp1.y теперь зажат близко к apex уровню (не к полной h*0.16
        // что давало tall bulge выше апекса). Берём точку чуть ниже
        // середины между neckY и apexY, масштабируя по t. Результат:
        // curve плавно арочит от шейки вверх к куполу без overshoot,
        // и макушка остаётся закруглённой даже при blob=1.
        let topArcHalfway = neckY + (apexY - neckY) * 0.55 * t

        let path = UIBezierPath()
        path.move(to: CGPoint(x: neckLeftX, y: neckY))

        // Левая шейка → апекс.
        path.addCurve(
            to: CGPoint(x: apexX, y: apexY),
            controlPoint1: CGPoint(
                x: neckLeftX,
                y: topArcHalfway
            ),
            controlPoint2: CGPoint(
                x: apexX - neckHalf * 0.95,
                y: apexCpY
            )
        )

        // Апекс → правая шейка. Симметрично.
        path.addCurve(
            to: CGPoint(x: neckRightX, y: neckY),
            controlPoint1: CGPoint(
                x: apexX + neckHalf * 0.95,
                y: apexCpY
            ),
            controlPoint2: CGPoint(
                x: neckRightX,
                y: topArcHalfway
            )
        )

        // Правая сторона: быстро распухает после шейки
        path.addCurve(
            to: CGPoint(x: rightBellyX, y: bellyY),
            controlPoint1: CGPoint(
                x: neckRightX + w * 0.16 * t,
                y: shoulderY
            ),
            controlPoint2: CGPoint(
                x: rect.maxX + w * 0.06 * t,
                y: rect.minY + h * 0.48
            )
        )

        // Правый низ к нижнему центру. "Inward" смещения
        // cp1/cp2 пропорциональны t — при t=0 control points ложатся
        // на край rect, давая прямую грань.
        path.addCurve(
            to: CGPoint(x: bottomMidX, y: bottomY),
            controlPoint1: CGPoint(
                x: rect.maxX - w * 0.03 * t,
                y: rect.minY + h * (1.0 - 0.14 * t)
            ),
            controlPoint2: CGPoint(
                x: rect.midX + w * 0.17 * t + anchorBias * 0.7,
                y: rect.maxY + h * 0.025 * t
            )
        )

        // Нижний центр к левому низу
        path.addCurve(
            to: CGPoint(x: leftBellyX, y: bellyY),
            controlPoint1: CGPoint(
                x: rect.midX - w * 0.17 * t + anchorBias * 0.7,
                y: rect.maxY + h * 0.025 * t
            ),
            controlPoint2: CGPoint(
                x: rect.minX + w * 0.03 * t,
                y: rect.minY + h * (1.0 - 0.14 * t)
            )
        )

        // Левая сторона обратно к шейке
        path.addCurve(
            to: CGPoint(x: neckLeftX, y: neckY),
            controlPoint1: CGPoint(
                x: rect.minX - w * 0.06 * t,
                y: rect.minY + h * 0.48
            ),
            controlPoint2: CGPoint(
                x: neckLeftX - w * 0.16 * t,
                y: shoulderY
            )
        )

        path.close()
        return path.cgPath
    }

    // MARK: - Blob timing

    private static func blobAmount(for progress: CGFloat) -> CGFloat {
        // Симметричный bell на всю длительность: blob = sin(π·t).
        // Пик на phaseT = 0.5, ноль на phaseT = 0 и = 1. Без плато —
        // груша нигде "не висит", форма за единую плавную дугу
        // проходит от rect (на старте) через пиковую каплю и обратно
        // в rect (в конце). Все остальные хореографии (source fade,
        // dest fade, spring settle) тоже теперь [0, 1] — всё идёт
        // параллельно, в одном темпе.
        let t = max(0, min(1, progress))
        return sin(.pi * t)
    }

    private static func topDomeAmount(for progress: CGFloat, hostHeight: CGFloat) -> CGFloat {
        let blob = blobAmount(for: progress)
        return min(40, hostHeight * 0.16) * blob
    }

    private static func sinWindow(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        guard t > a, t < b, b > a else { return 0 }
        let normalized = (t - a) / (b - a)
        return sin(normalized * .pi)
    }

    // MARK: - Easing helpers

    private static func springProgress(_ t: CGFloat, damping: CGFloat) -> CGFloat {
        // Cubic ease-out: `1 - (1 - t)³`. Asymmetric S-curve —
        // velocity at τ=0 is 3× the average rate (snappy launch),
        // velocity at τ=1 is 0 (gentle landing). Reads as "the
        // motion takes off quickly and resolves softly", which is
        // the standard fluid-motion shape (close cousin of CSS
        // `ease-out`, Material's "decelerate easing", iOS UIKit's
        // `.easeOut`).
        //
        // Symmetric smootherstep (the previous curve here) is
        // C²-smooth but starts AND ends slowly — it read as
        // "wooden" because the motion never had a moment of
        // commitment at the launch.
        //
        // ~87.5 % of the visible motion happens in the first half
        // of the timeline. Combined with the raised-cosine end-
        // bounce on `phaseT`, the second half is dedicated to the
        // soft landing + 2.5 % scale breathe.
        //
        // `damping` is unused — kept in the signature for call-
        // site stability (the controller still passes it from
        // `morphDamping` constants).
        _ = damping
        let inv = 1 - max(0, min(1, t))
        return 1 - inv * inv * inv
    }

    private static func cubicBezier(progress: CGFloat, cp1: CGPoint, cp2: CGPoint) -> CGFloat {
        var u = progress
        for _ in 0..<6 {
            let mu = 1 - u
            let x = 3 * mu * mu * u * cp1.x + 3 * mu * u * u * cp2.x + u * u * u
            let dx = 3 * mu * mu * cp1.x + 6 * mu * u * (cp2.x - cp1.x) + 3 * u * u * (1 - cp2.x)
            guard abs(dx) > 1e-6 else { break }
            let nextU = u - (x - progress) / dx
            u = max(0, min(1, nextU))
        }
        let mu = 1 - u
        return 3 * mu * mu * u * cp1.y + 3 * mu * u * u * cp2.y + u * u * u
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Quintic ease-in-out (Ken Perlin's smootherstep). Compared to
    /// `smoothstep`, it's `C²`-continuous at both endpoints — zero
    /// velocity AND zero acceleration at `t = 0` and `t = 1`. Reads
    /// as significantly smoother for ease-in-out curves at high
    /// refresh rates: there's no second-derivative kink at the
    /// boundaries, so the perceptual transition into and out of
    /// motion is gentler.
    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (6 * t - 15) + 10)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func lerpRect(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: lerp(a.minX, b.minX, t),
            y: lerp(a.minY, b.minY, t),
            width: lerp(a.width, b.width, t),
            height: lerp(a.height, b.height, t)
        )
    }
}
