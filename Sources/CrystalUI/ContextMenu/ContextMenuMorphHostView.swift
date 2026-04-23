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

    let glass: UIVisualEffectView
    let sourceContent = UIView()
    let destinationContent = UIView()

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

    private let shapeMaskLayer = CAShapeLayer()

    private static let collapsedShadowRadius: CGFloat = 12.0
    private static let expandedShadowRadius: CGFloat = 28.0
    private static let collapsedShadowOpacity: Float = 0.10
    private static let expandedShadowOpacity: Float = 0.16
    private static let shadowOffset = CGSize(width: 0, height: 6)

    // MARK: - Init

    init(effect: UIVisualEffect) {
        self.glass = UIVisualEffectView(effect: effect)
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

        shapeMaskLayer.fillColor = UIColor.black.cgColor
        layer.mask = shapeMaskLayer

        addSubview(glass)

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

        let tolerance: CGFloat = 1.0
        if abs(metrics.expandedFrame.minX - metrics.collapsedFrame.minX) <= tolerance {
            xAnchor = 0.0
        } else if abs(metrics.expandedFrame.maxX - metrics.collapsedFrame.maxX) <= tolerance {
            xAnchor = 1.0
        } else {
            xAnchor = 0.5
        }

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
        updateForProgress(surfaceProgress: value, phaseProgress: phase)
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

    private func updateForProgress(surfaceProgress: CGFloat, phaseProgress: CGFloat) {
        guard let metrics else { return }

        let gt = max(0, min(1, surfaceProgress))
        let phaseT = max(0, min(1, phaseProgress))

        let lerpFrame = Self.lerpRect(metrics.collapsedFrame, metrics.expandedFrame, gt)
        let baseCorner = Self.lerp(metrics.collapsedCornerRadius, metrics.expandedCornerRadius, gt)

        let blob = Self.blobAmount(for: phaseT)
        let topDome = Self.topDomeAmount(for: phaseT, hostHeight: lerpFrame.height)

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
            + 8 * blob
        let shadowOpacity = Float(
            Self.lerp(
                CGFloat(Self.collapsedShadowOpacity),
                CGFloat(Self.expandedShadowOpacity),
                gt
            ) + 0.02 * blob
        )

        // Параллельная хореография — source, dest и blob происходят
        // одновременно, а не по очереди. Source начинает исчезать
        // сразу с t=0, dest начинает появляться уже с t=0.10 (когда
        // source ещё наполовину видим), blob активен почти весь
        // морф. Зритель видит непрерывное "плавление" одного в
        // другое, а не последовательные фазы "сначала ушёл button,
        // потом плыл blob, потом появились ряды".
        let sourceFadeOut = Self.smoothstep(0.0, 0.38, phaseT)
        let sourceAlpha = max(0, 1 - sourceFadeOut)
        let sourceScale = 1.0 - 0.08 * sourceFadeOut

        let destFadeIn = Self.smoothstep(0.10, 0.62, phaseT)
        let destAlpha = destFadeIn
        let destTranslateY = (1 - destFadeIn) * 8

        let springExcess: CGFloat
        if surfaceProgress > 1 {
            springExcess = surfaceProgress - 1
        } else if surfaceProgress < 0 {
            springExcess = surfaceProgress
        } else {
            springExcess = 0
        }

        let springScaleX: CGFloat
        if abs(xAnchor - 0.5) < 0.01 {
            springScaleX = 1 + springExcess
        } else {
            springScaleX = 1.0
        }
        let springScaleY = 1 + springExcess

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let anchorPositionX = bulgedFrame.minX + bulgedFrame.width * xAnchor
        let anchorPositionY = bulgedFrame.minY + bulgedFrame.height * yAnchor

        bounds = CGRect(origin: .zero, size: bulgedFrame.size)
        layer.position = CGPoint(x: anchorPositionX, y: anchorPositionY)
        transform = CGAffineTransform(scaleX: springScaleX, y: springScaleY)

        glass.frame = bounds
        glass.layer.cornerRadius = 0

        let shapePath = Self.makeMorphPath(
            in: bounds,
            cornerRadius: cornerRadius,
            blob: blob,
            xAnchor: xAnchor,
            topDome: topDome
        )

        shapeMaskLayer.frame = bounds
        shapeMaskLayer.path = shapePath

        layer.shadowPath = shapePath
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity

        let sourceLocalOrigin = CGPoint(
            x: metrics.collapsedFrame.minX - bulgedFrame.minX,
            y: metrics.collapsedFrame.minY - bulgedFrame.minY
        )
        sourceContent.transform = .identity
        sourceContent.frame = CGRect(origin: sourceLocalOrigin, size: metrics.collapsedFrame.size)
        sourceContent.alpha = sourceAlpha
        sourceContent.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)

        let destLocalOrigin = CGPoint(
            x: metrics.expandedFrame.minX - bulgedFrame.minX,
            y: metrics.expandedFrame.minY - bulgedFrame.minY
        )
        destinationContent.transform = .identity
        destinationContent.frame = CGRect(origin: destLocalOrigin, size: metrics.expandedFrame.size)
        destinationContent.alpha = destAlpha
        destinationContent.transform = CGAffineTransform(translationX: 0, y: destTranslateY)

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

        if t < 0.001 {
            return UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
        }

        let w = rect.width
        let h = rect.height
        let midX = rect.midX

        // Центр массы слегка уходит к якорю, но не слишком,
        // чтобы форма не казалась косой.
        let anchorBias = (xAnchor - 0.5) * w * 0.12 * t

        // Узкая шейка. Это один из главных признаков капли.
        let neckWidth = max(16, w * (0.48 - 0.18 * t))
        let neckHalf = neckWidth * 0.5

        // Верхний пик.
        let apexLift = min(h * 0.18, topDome + h * 0.04 * t)

        // Уровень шейки.
        let neckY = rect.minY + max(8, topDome * (0.78 + 0.18 * t))

        // Плечи ближе к верху, пузо ниже центра.
        let shoulderY = rect.minY + h * (0.24 + 0.03 * t)
        let bellyY = rect.minY + h * (0.60 + 0.05 * t)

        // Ширина тела.
        let bellyInset = max(4, w * (0.05 - 0.015 * t))
        let leftBellyX = rect.minX + bellyInset + anchorBias * 0.25
        let rightBellyX = rect.maxX - bellyInset + anchorBias * 0.25

        // Низ собранный, не плоский.
        let bottomY = rect.maxY - max(2, h * 0.03 * t)
        let bottomMidX = rect.midX + anchorBias * 0.55

        let neckLeftX = midX - neckHalf + anchorBias
        let neckRightX = midX + neckHalf + anchorBias
        let apexX = midX + anchorBias
        let apexY = rect.minY - apexLift * 0.22

        let path = UIBezierPath()
        path.move(to: CGPoint(x: neckLeftX, y: neckY))

        // Левая шейка → апекс
        path.addCurve(
            to: CGPoint(x: apexX, y: apexY),
            controlPoint1: CGPoint(
                x: neckLeftX,
                y: neckY - h * 0.16
            ),
            controlPoint2: CGPoint(
                x: apexX - neckHalf * 0.95,
                y: rect.minY - apexLift * 0.08
            )
        )

        // Апекс → правая шейка
        path.addCurve(
            to: CGPoint(x: neckRightX, y: neckY),
            controlPoint1: CGPoint(
                x: apexX + neckHalf * 0.95,
                y: rect.minY - apexLift * 0.08
            ),
            controlPoint2: CGPoint(
                x: neckRightX,
                y: neckY - h * 0.16
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

        // Правый низ к нижнему центру
        path.addCurve(
            to: CGPoint(x: bottomMidX, y: bottomY),
            controlPoint1: CGPoint(
                x: rect.maxX - w * 0.03,
                y: rect.minY + h * 0.86
            ),
            controlPoint2: CGPoint(
                x: rect.midX + w * 0.17 + anchorBias * 0.7,
                y: rect.maxY + h * 0.025 * t
            )
        )

        // Нижний центр к левому низу
        path.addCurve(
            to: CGPoint(x: leftBellyX, y: bellyY),
            controlPoint1: CGPoint(
                x: rect.midX - w * 0.17 + anchorBias * 0.7,
                y: rect.maxY + h * 0.025 * t
            ),
            controlPoint2: CGPoint(
                x: rect.minX + w * 0.03,
                y: rect.minY + h * 0.86
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
        // Окно blob должно полностью закрыться ДО того, как
        // пружина дойдёт до пика overshoot (τ ≈ 0.58 с новой
        // кривой springProgress). Иначе на финальной фазе blob
        // падает с малого положительного до нуля и форма
        // переключается с капли на rounded rect (см.
        // `guard blob > 0.001` в `makeMorphPath`) — визуально
        // читается как рывок.
        //
        // Rise 0.02…0.20 оставляем широким для параллельной
        // хореографии с source/dest. Fall 0.20…0.45 — blob = 0 к
        // phaseT = 0.45, дальше (0.45…1.0, больше половины
        // длительности) меню — чистый rounded rect, и пружинный
        // settle работает без рывков формы.
        let rise = smoothstep(0.02, 0.20, progress)
        let fall = 1.0 - smoothstep(0.20, 0.45, progress)
        return rise * fall
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
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        // Step response of an underdamped harmonic oscillator — the
        // same math UIKit uses internally for `UISpringTimingParameters`
        // (which drives the `.fluidMorph` variant, and which the user
        // prefers for its smoothness over the old cubic-bezier
        // approximation that replaced this function earlier).
        //
        //   y(τ) = 1 − e^(−ζωτ) · (cos(ωd·τ) + (ζ/√(1−ζ²)) · sin(ωd·τ))
        //   ωd   = ω · √(1 − ζ²)                 (damped frequency)
        //
        // ω = 2.5π chosen so that:
        //   • The first overshoot peak lands around τ ≈ 0.58, i.e.
        //     just after mid-animation — the user sees a clear "arrive
        //     → gentle bounce → settle" arc rather than a cubic-bezier
        //     hockey stick.
        //   • e^(−ζω) is small enough by τ = 1 that the transient has
        //     essentially decayed (≈ 0.3 % residual at ζ = 0.72), so
        //     y(1) lands on 1 without explicit normalization.
        //
        // Damping ratio `ζ` comes from the caller. At ζ = 0.72 the peak
        // overshoot is ≈ 3.8 % — a visible but gentle "light spring"
        // with a late deceleration.
        let zeta = Double(max(0.01, min(0.99, damping)))
        let omega: Double = 2.5 * .pi
        let omegaD = omega * sqrt(1 - zeta * zeta)
        let B = zeta / sqrt(1 - zeta * zeta)
        let tau = Double(t)
        let decay = exp(-zeta * omega * tau)
        let oscillation = cos(omegaD * tau) + B * sin(omegaD * tau)
        return CGFloat(1 - decay * oscillation)
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
