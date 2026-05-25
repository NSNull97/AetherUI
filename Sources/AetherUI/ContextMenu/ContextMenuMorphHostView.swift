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
    var destinationRevealProgressChanged: ((CGFloat) -> Void)?

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

    /// When `true`, the subtle organic deformation is suppressed and
    /// the host stays a lerping rounded rectangle. Kept for dismiss /
    /// cancellation paths where a completely predictable collapse is
    /// preferable to any surface-tension pulse.
    var suppressBlob: Bool = false

    private static let collapsedShadowRadius: CGFloat = 10.0
    private static let peakShadowRadius: CGFloat = 28.0
    private static let settledShadowRadius: CGFloat = 22.0
    private static let collapsedShadowOpacity: Float = 0.04
    private static let peakShadowOpacity: Float = 0.18
    private static let settledShadowOpacity: Float = 0.12
    private static let collapsedShadowOffsetY: CGFloat = 3.0
    private static let peakShadowOffsetY: CGFloat = 12.0
    private static let settledShadowOffsetY: CGFloat = 8.0

    // MARK: - Init

    init(isDark: Bool) {
        self.glass = MenuGlassSurfaceView(isDark: isDark)
        super.init(frame: .zero)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: Self.collapsedShadowOffsetY)
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
        sourceContent.clipsToBounds = true
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
        let maximumFramesPerSecond = max(60, UIScreen.main.maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let preferredFrameRate = Float(min(120, maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(80, preferredFrameRate),
                maximum: preferredFrameRate,
                preferred: preferredFrameRate
            )
        } else {
            link.preferredFramesPerSecond = maximumFramesPerSecond
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

        let phaseT = max(0, min(1, phaseProgress))
        let geometryT = max(0, min(1.06, surfaceProgress))
        let materialT = Self.smootherstep(0.08, 0.72, phaseT)

        let midX = Self.lerp(metrics.collapsedFrame.midX, metrics.expandedFrame.midX, geometryT)
        let midY = Self.lerp(metrics.collapsedFrame.midY, metrics.expandedFrame.midY, geometryT)
        var width = Self.lerp(metrics.collapsedFrame.width, metrics.expandedFrame.width, geometryT)
        var height = Self.lerp(metrics.collapsedFrame.height, metrics.expandedFrame.height, geometryT)

        // Surface tension stays deliberately low: enough to prevent a
        // wooden rectangle scale, never enough to become a teardrop.
        let blob = suppressBlob ? 0.0 : 0.06 * sin(.pi * phaseT)
        let dx = abs(metrics.expandedFrame.midX - metrics.collapsedFrame.midX)
        let dy = abs(metrics.expandedFrame.midY - metrics.collapsedFrame.midY)
        if dy >= dx {
            height *= 1.0 + blob
            width *= 1.0 - blob * 0.35
        } else {
            width *= 1.0 + blob
            height *= 1.0 - blob * 0.35
        }

        let bulgedFrame = CGRect(
            x: midX - width / 2,
            y: midY - height / 2,
            width: width,
            height: height
        )

        let pillCorner = min(width, height) / 2
        let earlyCorner = Self.lerp(
            metrics.collapsedCornerRadius,
            pillCorner,
            Self.smootherstep(0.0, 0.35, phaseT)
        )
        let baseCorner = Self.lerp(
            earlyCorner,
            metrics.expandedCornerRadius,
            Self.smootherstep(0.35, 0.9, phaseT)
        )
        let cornerRadius = baseCorner + blob * min(baseCorner * 0.08, 3.0)

        let shadowPeakT = Self.smootherstep(0.0, 0.45, materialT)
        let shadowSettleT = Self.smootherstep(0.45, 1.0, materialT)
        let shadowOpacityValue = Self.lerp(
            Self.lerp(CGFloat(Self.collapsedShadowOpacity), CGFloat(Self.peakShadowOpacity), shadowPeakT),
            CGFloat(Self.settledShadowOpacity),
            shadowSettleT
        )
        let shadowRadius = Self.lerp(
            Self.lerp(Self.collapsedShadowRadius, Self.peakShadowRadius, shadowPeakT),
            Self.settledShadowRadius,
            shadowSettleT
        )
        let shadowOffsetY = Self.lerp(
            Self.lerp(Self.collapsedShadowOffsetY, Self.peakShadowOffsetY, shadowPeakT),
            Self.settledShadowOffsetY,
            shadowSettleT
        )

        let sourceFade = Self.smootherstep(0.08, 0.28, phaseT)
        let sourceAlpha = 1.0 - sourceFade
        let sourceScale = 1.0 - 0.04 * sourceFade

        let destReveal = Self.smootherstep(0.18, 0.68, phaseT)
        let destAlpha = destReveal
        let destTranslateY = (1.0 - Self.smootherstep(0.18, 0.60, phaseT)) * 6.0

        let isAnimatingOpen = displayLink != nil && animTo > animFrom
        let pressureT = isAnimatingOpen ? Self.smootherstep(0.0, 0.14, rawTime) : 1.0
        let pressureScale = isAnimatingOpen ? Self.lerp(0.985, 1.0, pressureT) : 1.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let anchorPositionX = bulgedFrame.minX + bulgedFrame.width * xAnchor
        let anchorPositionY = bulgedFrame.minY + bulgedFrame.height * yAnchor

        bounds = CGRect(origin: .zero, size: bulgedFrame.size)
        layer.position = CGPoint(x: anchorPositionX, y: anchorPositionY)
        transform = CGAffineTransform(scaleX: pressureScale, y: pressureScale)

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
        layer.shadowOpacity = Float(shadowOpacityValue)
        layer.shadowOffset = CGSize(width: 0, height: shadowOffsetY)
        glass.updateMaterialThickness(materialT)

        let sourceLocalOrigin = CGPoint(
            x: metrics.collapsedFrame.minX - bulgedFrame.minX,
            y: metrics.collapsedFrame.minY - bulgedFrame.minY
        )
        sourceContent.layer.frame = CGRect(origin: sourceLocalOrigin, size: metrics.collapsedFrame.size)
        sourceContent.alpha = sourceAlpha
        sourceContent.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)

        let destLocalOrigin = CGPoint(
            x: metrics.expandedFrame.minX - bulgedFrame.minX,
            y: metrics.expandedFrame.minY - bulgedFrame.minY
        )
        destinationContent.layer.frame = CGRect(origin: destLocalOrigin, size: metrics.expandedFrame.size)
        destinationContent.alpha = destAlpha
        destinationContent.transform = CGAffineTransform(translationX: 0, y: destTranslateY)
        destinationRevealProgressChanged?(destReveal)

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
        dampedSpring01(t, response: 0.48, dampingRatio: damping)
    }

    private static func dampedSpring01(_ rawT: CGFloat, response: CGFloat, dampingRatio: CGFloat) -> CGFloat {
        let t = max(0.0, min(1.0, rawT))
        let response = max(0.08, response)
        let omega0 = 2.0 * CGFloat.pi / response
        let zeta = max(0.01, dampingRatio)

        if zeta < 1.0 {
            let wd = omega0 * sqrt(1.0 - zeta * zeta)
            let envelope = exp(-zeta * omega0 * t)
            let c = zeta / sqrt(1.0 - zeta * zeta)
            return 1.0 - envelope * (cos(wd * t) + c * sin(wd * t))
        } else {
            let omega = omega0
            return 1.0 - exp(-omega * t) * (1.0 + omega * t)
        }
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
