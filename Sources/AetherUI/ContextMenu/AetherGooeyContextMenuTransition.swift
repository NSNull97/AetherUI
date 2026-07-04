import UIKit
import Metal
import MetalKit
import QuartzCore
import os

// MARK: - Public API

public enum AetherGooeyCornerRadiusPolicy {
    case fixed(CGFloat)
    case fromLayer
    case fromPresentationLayer
    case capsule
}

public enum AetherContextMenuPlacement: Equatable {
    case above
    case below
    case leading
    case trailing
    case overlapping
    case custom(anchor: CGPoint)
}

public enum AetherGooeyTransitionPhase {
    case opening
    case closing
}

public struct AetherGooeyAccessibilitySettings: Equatable {
    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var increasedContrast: Bool

    public init(
        reduceMotion: Bool,
        reduceTransparency: Bool,
        increasedContrast: Bool
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increasedContrast = increasedContrast
    }

    public static var current: AetherGooeyAccessibilitySettings {
        AetherGooeyAccessibilitySettings(
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            reduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
            increasedContrast: UIAccessibility.isDarkerSystemColorsEnabled
        )
    }
}

public struct AetherGooeyContextMenuTransitionConfiguration {
    public var durationOpen: TimeInterval
    public var durationClose: TimeInterval

    public var springDamping: CGFloat
    public var springResponse: CGFloat

    public var connectorMaximumLength: CGFloat
    public var connectorMinimumThickness: CGFloat
    public var connectorMaximumThickness: CGFloat

    public var sourceCornerRadiusPolicy: AetherGooeyCornerRadiusPolicy
    public var menuCornerRadiusPolicy: AetherGooeyCornerRadiusPolicy

    public var glassStyle: SystemGlassEffectStyle
    public var blurIntensity: CGFloat
    public var tintAlpha: CGFloat
    public var strokeAlpha: CGFloat
    public var shadowAlpha: CGFloat
    public var highlightAlpha: CGFloat

    public var allowsLensingApproximation: Bool
    public var respectsReduceMotion: Bool
    public var respectsReduceTransparency: Bool
    public var debugShowsControlPoints: Bool

    public init(
        durationOpen: TimeInterval,
        durationClose: TimeInterval,
        springDamping: CGFloat,
        springResponse: CGFloat,
        connectorMaximumLength: CGFloat,
        connectorMinimumThickness: CGFloat,
        connectorMaximumThickness: CGFloat,
        sourceCornerRadiusPolicy: AetherGooeyCornerRadiusPolicy,
        menuCornerRadiusPolicy: AetherGooeyCornerRadiusPolicy,
        glassStyle: SystemGlassEffectStyle,
        blurIntensity: CGFloat,
        tintAlpha: CGFloat,
        strokeAlpha: CGFloat,
        shadowAlpha: CGFloat,
        highlightAlpha: CGFloat,
        allowsLensingApproximation: Bool,
        respectsReduceMotion: Bool,
        respectsReduceTransparency: Bool,
        debugShowsControlPoints: Bool
    ) {
        self.durationOpen = durationOpen
        self.durationClose = durationClose
        self.springDamping = springDamping
        self.springResponse = springResponse
        self.connectorMaximumLength = connectorMaximumLength
        self.connectorMinimumThickness = connectorMinimumThickness
        self.connectorMaximumThickness = connectorMaximumThickness
        self.sourceCornerRadiusPolicy = sourceCornerRadiusPolicy
        self.menuCornerRadiusPolicy = menuCornerRadiusPolicy
        self.glassStyle = glassStyle
        self.blurIntensity = blurIntensity
        self.tintAlpha = tintAlpha
        self.strokeAlpha = strokeAlpha
        self.shadowAlpha = shadowAlpha
        self.highlightAlpha = highlightAlpha
        self.allowsLensingApproximation = allowsLensingApproximation
        self.respectsReduceMotion = respectsReduceMotion
        self.respectsReduceTransparency = respectsReduceTransparency
        self.debugShowsControlPoints = debugShowsControlPoints
    }
}

public extension AetherGooeyContextMenuTransitionConfiguration {
    static func `default`(
        appearance: AetherAppearance
    ) -> AetherGooeyContextMenuTransitionConfiguration {
        switch appearance.style {
        case .iOS26:
            return .init(
                durationOpen: 0.58,
                durationClose: 0.48,
                springDamping: 0.82,
                springResponse: 0.34,
                connectorMaximumLength: 136.0,
                connectorMinimumThickness: 8.0,
                connectorMaximumThickness: 28.0,
                sourceCornerRadiusPolicy: .fromPresentationLayer,
                menuCornerRadiusPolicy: .fromPresentationLayer,
                glassStyle: .regular,
                blurIntensity: 0.75,
                tintAlpha: 0.18,
                strokeAlpha: 0.18,
                shadowAlpha: 0.20,
                highlightAlpha: 0.35,
                allowsLensingApproximation: true,
                respectsReduceMotion: true,
                respectsReduceTransparency: true,
                debugShowsControlPoints: false
            )
        case .iOS27:
            return .init(
                durationOpen: 0.56,
                durationClose: 0.48,
                springDamping: 0.88,
                springResponse: 0.32,
                connectorMaximumLength: 132.0,
                connectorMinimumThickness: 10.0,
                connectorMaximumThickness: 32.0,
                sourceCornerRadiusPolicy: .fromPresentationLayer,
                menuCornerRadiusPolicy: .fromPresentationLayer,
                glassStyle: .strong,
                blurIntensity: 0.90,
                tintAlpha: 0.22,
                strokeAlpha: 0.32,
                shadowAlpha: 0.24,
                highlightAlpha: 0.30,
                allowsLensingApproximation: true,
                respectsReduceMotion: true,
                respectsReduceTransparency: true,
                debugShowsControlPoints: false
            )
        }
    }
}

public protocol AetherContextMenuTransitioning: AnyObject {
    func animateOpen(
        sourceView: UIView,
        menuView: UIView,
        containerView: UIView,
        placement: AetherContextMenuPlacement,
        completion: @escaping (Bool) -> Void
    )

    func animateClose(
        sourceView: UIView?,
        menuView: UIView,
        containerView: UIView,
        placement: AetherContextMenuPlacement,
        completion: @escaping (Bool) -> Void
    )

    func cancel()
}

public struct AetherGooeyGeometry: Equatable {
    public var sourceFrameInContainer: CGRect
    public var menuFrameInContainer: CGRect

    public var sourceCornerRadius: CGFloat
    public var menuCornerRadius: CGFloat

    public var sourceCenter: CGPoint
    public var menuCenter: CGPoint

    public var connectorStartPoint: CGPoint
    public var connectorEndPoint: CGPoint

    public var placement: AetherContextMenuPlacement
    public var distance: CGFloat

    public init(
        sourceFrameInContainer: CGRect,
        menuFrameInContainer: CGRect,
        sourceCornerRadius: CGFloat,
        menuCornerRadius: CGFloat,
        sourceCenter: CGPoint,
        menuCenter: CGPoint,
        connectorStartPoint: CGPoint,
        connectorEndPoint: CGPoint,
        placement: AetherContextMenuPlacement,
        distance: CGFloat
    ) {
        self.sourceFrameInContainer = sourceFrameInContainer
        self.menuFrameInContainer = menuFrameInContainer
        self.sourceCornerRadius = sourceCornerRadius
        self.menuCornerRadius = menuCornerRadius
        self.sourceCenter = sourceCenter
        self.menuCenter = menuCenter
        self.connectorStartPoint = connectorStartPoint
        self.connectorEndPoint = connectorEndPoint
        self.placement = placement
        self.distance = distance
    }
}

public protocol AetherContextMenuContentAnimatable: AnyObject {
    func prepareForGooeyOpen()
    func updateGooeyOpenProgress(_ progress: CGFloat)
    func finishGooeyOpen()

    func prepareForGooeyClose()
    func updateGooeyCloseProgress(_ progress: CGFloat)
    func finishGooeyClose()
}

public final class AetherGooeyContextMenuTransition: AetherContextMenuTransitioning {
    public let configuration: AetherGooeyContextMenuTransitionConfiguration

    private var overlayView: AetherGooeyTransitionOverlayView?
    private var animator: AetherGooeyAnimator?
    private var cleanup: (() -> Void)?
    private var completion: ((Bool) -> Void)?
    private var signpostID: OSSignpostID?

    public init(configuration: AetherGooeyContextMenuTransitionConfiguration) {
        self.configuration = configuration
    }

    deinit {
        animator?.cancel()
        overlayView?.removeFromSuperview()
    }

    public func animateOpen(
        sourceView: UIView,
        menuView: UIView,
        containerView: UIView,
        placement: AetherContextMenuPlacement,
        completion: @escaping (Bool) -> Void
    ) {
        cancel()

        containerView.layoutIfNeeded()
        menuView.layoutIfNeeded()
        let geometry = captureGooeyGeometry(
            sourceView: sourceView,
            menuView: menuView,
            containerView: containerView,
            placement: placement,
            sourceCornerRadiusPolicy: configuration.sourceCornerRadiusPolicy,
            menuCornerRadiusPolicy: configuration.menuCornerRadiusPolicy
        )
        let animatables = Self.collectContentAnimatables(in: menuView)
        let isDark = menuView.traitCollection.userInterfaceStyle == .dark
        let overlay = AetherGooeyTransitionOverlayView(
            configuration: configuration,
            isDark: isDark
        )
        overlay.frame = containerView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        Self.installOverlay(overlay, in: containerView, above: menuView)
        overlay.setNeedsLayout()
        overlay.layoutIfNeeded()
        self.overlayView = overlay

        let menuInitialAlpha = menuView.alpha
        let menuTargetAlpha = menuInitialAlpha > 0.01 ? menuInitialAlpha : 1.0
        let menuOriginalFrame = menuView.frame
        let menuOriginalTransform = menuView.transform
        let menuInitialInteraction = menuView.isUserInteractionEnabled
        let menuTargetInteraction = true
        let menuGlassSurface = menuView as? MenuGlassSurfaceView
        let sourceOriginalAlpha = sourceView.alpha
        let sourceOriginalInteraction = sourceView.isUserInteractionEnabled
        animatables.forEach { $0.finishGooeyOpen() }
        overlay.setMenuPreviewImage(nil)
        overlay.setSourcePreviewImage(Self.snapshotViewPreview(
            view: sourceView,
            targetAlpha: sourceOriginalAlpha
        ))
        overlay.update(
            geometry: geometry,
            progress: 0.0,
            phase: .opening,
            configuration: configuration
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        menuView.layer.removeAllAnimations()
        sourceView.layer.removeAllAnimations()
        sourceView.alpha = sourceOriginalAlpha
        sourceView.isUserInteractionEnabled = false
        menuView.alpha = menuTargetAlpha
        menuView.frame = menuOriginalFrame
        menuView.transform = menuOriginalTransform
        menuGlassSurface?.setGooeyMaterialSuppressed(true)
        menuGlassSurface?.updateMaterialThickness(0.0)
        menuView.isUserInteractionEnabled = false
        CATransaction.commit()

        cleanup = { [weak self, weak overlay, weak menuView, weak sourceView, weak menuGlassSurface] in
            self?.animator?.cancel()
            self?.animator = nil
            overlay?.removeFromSuperview()
            menuView?.layer.removeAllAnimations()
            menuGlassSurface?.setGooeyMaterialSuppressed(false)
            sourceView?.layer.removeAllAnimations()
        }
        self.completion = completion
        beginSignpost("GooeyOpen")

        let duration = adjustedDuration(
            base: configuration.durationOpen,
            settings: Self.accessibilitySettings(configuration: configuration)
        )
        let animator = AetherGooeyAnimator()
        self.animator = animator
        animator.animate(
            duration: duration,
            timing: .cubicBezier(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0),
            update: { [weak self, weak overlay, weak menuView, weak sourceView] rawProgress in
                guard let self, let overlay, let menuView, let sourceView else { return }
                let settings = Self.accessibilitySettings(configuration: self.configuration)
                let progress = self.visualProgress(rawProgress, settings: settings, phase: .opening)
                let materialProgress = Self.rangedProgress(progress, start: 0.84, end: 1.0)

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                overlay.update(
                    geometry: geometry,
                    progress: progress,
                    phase: .opening,
                    configuration: self.configuration
                )
                menuView.frame = menuOriginalFrame
                menuView.alpha = menuTargetAlpha
                menuView.transform = menuOriginalTransform
                menuGlassSurface?.updateMaterialThickness(materialProgress)
                sourceView.alpha = sourceOriginalAlpha * (1.0 - Self.rangedProgress(progress, start: 0.02, end: 0.38))
                CATransaction.commit()
            },
            completion: { [weak self, weak overlay, weak menuView, weak sourceView] finished in
                guard let self else { return }
                self.animator = nil
                self.endSignpost("GooeyOpen")
                overlay?.removeFromSuperview()

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if finished {
                    menuView?.frame = menuOriginalFrame
                    menuView?.alpha = menuTargetAlpha
                    menuView?.transform = menuOriginalTransform
                    menuGlassSurface?.setGooeyMaterialSuppressed(false)
                    menuGlassSurface?.updateMaterialThickness(1.0)
                    menuView?.isUserInteractionEnabled = menuTargetInteraction
                    sourceView?.alpha = 0.0
                    sourceView?.isUserInteractionEnabled = false
                    animatables.forEach { $0.finishGooeyOpen() }
                } else {
                    menuView?.frame = menuOriginalFrame
                    menuView?.alpha = menuInitialAlpha
                    menuView?.transform = menuOriginalTransform
                    menuGlassSurface?.setGooeyMaterialSuppressed(false)
                    menuGlassSurface?.updateMaterialThickness(menuInitialAlpha > 0.01 ? 1.0 : 0.0)
                    menuView?.isUserInteractionEnabled = menuInitialInteraction
                    sourceView?.alpha = sourceOriginalAlpha
                    sourceView?.isUserInteractionEnabled = sourceOriginalInteraction
                }
                CATransaction.commit()

                self.overlayView = nil
                self.cleanup = nil
                let completion = self.completion
                self.completion = nil
                completion?(finished)
            }
        )
    }

    public func animateClose(
        sourceView: UIView?,
        menuView: UIView,
        containerView: UIView,
        placement: AetherContextMenuPlacement,
        completion: @escaping (Bool) -> Void
    ) {
        cancel()

        containerView.layoutIfNeeded()
        menuView.layoutIfNeeded()
        let geometry = captureGooeyGeometry(
            sourceView: sourceView,
            menuView: menuView,
            containerView: containerView,
            placement: placement,
            sourceCornerRadiusPolicy: configuration.sourceCornerRadiusPolicy,
            menuCornerRadiusPolicy: configuration.menuCornerRadiusPolicy
        )
        let animatables = Self.collectContentAnimatables(in: menuView)
        let isDark = menuView.traitCollection.userInterfaceStyle == .dark
        let sourceOriginalAlpha = sourceView?.alpha
        let overlay = AetherGooeyTransitionOverlayView(
            configuration: configuration,
            isDark: isDark
        )
        overlay.frame = containerView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        Self.installOverlay(overlay, in: containerView, above: menuView)
        overlay.setNeedsLayout()
        overlay.layoutIfNeeded()
        self.overlayView = overlay

        let menuOriginalAlpha = menuView.alpha
        let menuOriginalFrame = menuView.frame
        let menuOriginalTransform = menuView.transform
        let menuOriginalInteraction = menuView.isUserInteractionEnabled
        let menuGlassSurface = menuView as? MenuGlassSurfaceView
        let sourceOriginalInteraction = sourceView?.isUserInteractionEnabled
        overlay.setMenuPreviewImage(nil)
        if let sourceView {
            overlay.setSourcePreviewImage(Self.snapshotViewPreview(
                view: sourceView,
                targetAlpha: 1.0
            ))
        }
        overlay.update(
            geometry: geometry,
            progress: 0.0,
            phase: .closing,
            configuration: configuration
        )
        animatables.forEach { $0.prepareForGooeyClose() }
        animatables.forEach { $0.updateGooeyCloseProgress(1.0) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        menuView.layer.removeAllAnimations()
        sourceView?.layer.removeAllAnimations()
        menuView.frame = menuOriginalFrame
        menuView.alpha = menuOriginalAlpha
        menuView.transform = menuOriginalTransform
        menuGlassSurface?.setGooeyMaterialSuppressed(true)
        menuGlassSurface?.updateMaterialThickness(1.0)
        menuView.isUserInteractionEnabled = false
        sourceView?.alpha = 0.0
        sourceView?.isUserInteractionEnabled = false
        CATransaction.commit()

        cleanup = { [weak self, weak overlay, weak menuView, weak sourceView, weak menuGlassSurface] in
            self?.animator?.cancel()
            self?.animator = nil
            overlay?.removeFromSuperview()
            menuView?.layer.removeAllAnimations()
            menuGlassSurface?.setGooeyMaterialSuppressed(false)
            sourceView?.layer.removeAllAnimations()
        }
        self.completion = completion
        beginSignpost("GooeyClose")

        let duration = adjustedDuration(
            base: configuration.durationClose,
            settings: Self.accessibilitySettings(configuration: configuration)
        )
        let animator = AetherGooeyAnimator()
        self.animator = animator
        animator.animate(
            duration: duration,
            timing: .cubicBezier(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0),
            update: { [weak self, weak overlay, weak menuView, weak sourceView] rawProgress in
                guard let self, let overlay, let menuView else { return }
                let settings = Self.accessibilitySettings(configuration: self.configuration)
                let progress = self.visualProgress(rawProgress, settings: settings, phase: .closing)
                let materialProgress = 1.0 - Self.rangedProgress(progress, start: 0.06, end: 0.28)

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                overlay.update(
                    geometry: geometry,
                    progress: progress,
                    phase: .closing,
                    configuration: self.configuration
                )
                menuView.frame = menuOriginalFrame
                menuView.alpha = menuOriginalAlpha
                menuView.transform = menuOriginalTransform
                menuGlassSurface?.updateMaterialThickness(materialProgress)
                if let sourceView {
                    sourceView.alpha = Self.rangedProgress(progress, start: 0.84, end: 1.0)
                }
                CATransaction.commit()
            },
            completion: { [weak self, weak overlay, weak menuView, weak sourceView] finished in
                guard let self else { return }
                self.animator = nil
                self.endSignpost("GooeyClose")
                overlay?.removeFromSuperview()

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if finished {
                    menuView?.frame = menuOriginalFrame
                    menuView?.alpha = 0.0
                    menuView?.transform = menuOriginalTransform
                    menuGlassSurface?.setGooeyMaterialSuppressed(false)
                    menuGlassSurface?.updateMaterialThickness(0.0)
                    menuView?.isUserInteractionEnabled = false
                    if sourceOriginalAlpha != nil {
                        sourceView?.alpha = 1.0
                    }
                    if let sourceOriginalInteraction {
                        sourceView?.isUserInteractionEnabled = sourceOriginalInteraction
                    }
                    animatables.forEach { $0.finishGooeyClose() }
                } else {
                    menuView?.frame = menuOriginalFrame
                    menuView?.alpha = menuOriginalAlpha
                    menuView?.transform = menuOriginalTransform
                    menuGlassSurface?.setGooeyMaterialSuppressed(false)
                    menuGlassSurface?.updateMaterialThickness(1.0)
                    menuView?.isUserInteractionEnabled = menuOriginalInteraction
                    if let sourceOriginalAlpha {
                        sourceView?.alpha = sourceOriginalAlpha
                    }
                    if let sourceOriginalInteraction {
                        sourceView?.isUserInteractionEnabled = sourceOriginalInteraction
                    }
                }
                CATransaction.commit()

                self.overlayView = nil
                self.cleanup = nil
                let completion = self.completion
                self.completion = nil
                completion?(finished)
            }
        )
    }

    public func cancel() {
        animator?.cancel()
        animator = nil
        overlayView?.removeFromSuperview()
        overlayView = nil
        cleanup?()
        cleanup = nil
        let completion = self.completion
        self.completion = nil
        completion?(false)
        signpostID = nil
    }

    private static func installOverlay(
        _ overlay: UIView,
        in containerView: UIView,
        above menuView: UIView
    ) {
        if menuView.superview === containerView {
            containerView.insertSubview(overlay, belowSubview: menuView)
        } else {
            containerView.addSubview(overlay)
        }
    }

    private static func snapshotMenuPreview(
        menuView: UIView,
        targetAlpha: CGFloat,
        revealContent: (() -> Void)?
    ) -> UIImage? {
        guard menuView.bounds.width > 1.0, menuView.bounds.height > 1.0 else {
            return nil
        }

        let originalAlpha = menuView.alpha
        let originalHidden = menuView.isHidden
        let originalTransform = menuView.transform
        let originalUserInteraction = menuView.isUserInteractionEnabled
        let restoredMaterialThickness = originalAlpha > 0.01 ? 1.0 : 0.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealContent?()
        menuView.isHidden = false
        menuView.alpha = max(0.01, targetAlpha)
        menuView.transform = .identity
        menuView.isUserInteractionEnabled = false
        (menuView as? MenuGlassSurfaceView)?.updateMaterialThickness(1.0)
        menuView.setNeedsLayout()
        menuView.layoutIfNeeded()
        CATransaction.commit()

        let renderView: UIView = (menuView as? MenuGlassSurfaceView)?.contentView ?? menuView
        let renderBounds = renderView.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = menuView.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: renderBounds, format: format).image { context in
            let didDraw = renderView.window != nil
                ? renderView.drawHierarchy(in: renderBounds, afterScreenUpdates: false)
                : false
            if !didDraw {
                renderView.layer.render(in: context.cgContext)
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        menuView.alpha = originalAlpha
        menuView.isHidden = originalHidden
        menuView.transform = originalTransform
        menuView.isUserInteractionEnabled = originalUserInteraction
        (menuView as? MenuGlassSurfaceView)?.updateMaterialThickness(restoredMaterialThickness)
        CATransaction.commit()

        return image
    }

    private static func snapshotViewPreview(
        view: UIView,
        targetAlpha: CGFloat
    ) -> UIImage? {
        guard view.bounds.width > 1.0, view.bounds.height > 1.0 else {
            return nil
        }

        let originalAlpha = view.alpha
        let originalHidden = view.isHidden
        let originalTransform = view.transform
        let originalUserInteraction = view.isUserInteractionEnabled

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.isHidden = false
        view.alpha = max(0.01, targetAlpha)
        view.transform = .identity
        view.isUserInteractionEnabled = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        CATransaction.commit()

        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            let didDraw = view.window != nil
                ? view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
                : false
            if !didDraw {
                view.layer.render(in: context.cgContext)
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.alpha = originalAlpha
        view.isHidden = originalHidden
        view.transform = originalTransform
        view.isUserInteractionEnabled = originalUserInteraction
        CATransaction.commit()

        return image
    }

    private static func makeMenuMaskLayer(for menuView: UIView) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = menuView.bounds
        layer.contentsScale = menuView.window?.screen.scale ?? UIScreen.main.scale
        layer.fillRule = .nonZero
        layer.fillColor = UIColor.black.cgColor
        return layer
    }

    private static func updateMenuMask(
        menuView: UIView,
        maskLayer: CAShapeLayer,
        containerPath: CGPath?
    ) {
        guard let containerPath else {
            maskLayer.path = nil
            return
        }
        var transform = CGAffineTransform(
            translationX: -menuView.frame.minX,
            y: -menuView.frame.minY
        )
        maskLayer.frame = menuView.bounds
        maskLayer.path = containerPath.copy(using: &transform)
    }

    private func adjustedDuration(
        base: TimeInterval,
        settings: AetherGooeyAccessibilitySettings
    ) -> TimeInterval {
        if configuration.respectsReduceMotion, settings.reduceMotion {
            return min(base, 0.16)
        }
        return base
    }

    private func visualProgress(
        _ progress: CGFloat,
        settings: AetherGooeyAccessibilitySettings,
        phase: AetherGooeyTransitionPhase
    ) -> CGFloat {
        let t = AetherGooeyMath.clamp(progress, 0.0, 1.0)
        if configuration.respectsReduceMotion, settings.reduceMotion {
            return AetherGooeyMath.smoothstep(t)
        }
        switch phase {
        case .opening:
            return t
        case .closing:
            return t
        }
    }

    private static func collectContentAnimatables(in root: UIView) -> [AetherContextMenuContentAnimatable] {
        var result: [AetherContextMenuContentAnimatable] = []
        func walk(_ view: UIView) {
            if let animatable = view as? AetherContextMenuContentAnimatable {
                result.append(animatable)
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return result
    }

    static func rangedProgress(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else {
            return value >= end ? 1.0 : 0.0
        }
        return AetherGooeyMath.smootherstep(start, end, value)
    }

    private static func accessibilitySettings(
        configuration: AetherGooeyContextMenuTransitionConfiguration
    ) -> AetherGooeyAccessibilitySettings {
        let current = AetherGooeyAccessibilitySettings.current
        return AetherGooeyAccessibilitySettings(
            reduceMotion: configuration.respectsReduceMotion && current.reduceMotion,
            reduceTransparency: configuration.respectsReduceTransparency && current.reduceTransparency,
            increasedContrast: current.increasedContrast
        )
    }

    private func beginSignpost(_ name: StaticString) {
        let id = OSSignpostID(log: AetherGooeyInstrumentation.log)
        signpostID = id
        os_signpost(.begin, log: AetherGooeyInstrumentation.log, name: name, signpostID: id)
    }

    private func endSignpost(_ name: StaticString) {
        guard let signpostID else { return }
        os_signpost(.end, log: AetherGooeyInstrumentation.log, name: name, signpostID: signpostID)
        self.signpostID = nil
    }
}

// MARK: - Geometry

public func captureGooeyGeometry(
    sourceView: UIView?,
    menuView: UIView,
    containerView: UIView,
    placement: AetherContextMenuPlacement
) -> AetherGooeyGeometry {
    captureGooeyGeometry(
        sourceView: sourceView,
        menuView: menuView,
        containerView: containerView,
        placement: placement,
        sourceCornerRadiusPolicy: .fromPresentationLayer,
        menuCornerRadiusPolicy: .fromPresentationLayer
    )
}

func captureGooeyGeometry(
    sourceView: UIView?,
    menuView: UIView,
    containerView: UIView,
    placement: AetherContextMenuPlacement,
    sourceCornerRadiusPolicy: AetherGooeyCornerRadiusPolicy,
    menuCornerRadiusPolicy: AetherGooeyCornerRadiusPolicy
) -> AetherGooeyGeometry {
    let menuFrame = AetherGooeyGeometryCapture.convertedFrame(
        view: menuView,
        in: containerView
    )
    let fallbackSource = AetherGooeyGeometryCapture.fallbackSourceFrame(
        menuFrame: menuFrame,
        placement: placement
    )
    let sourceFrame = sourceView.flatMap {
        AetherGooeyGeometryCapture.convertedFrame(view: $0, in: containerView)
    } ?? fallbackSource

    let pixelAlignedSource = AetherGooeyGeometryCapture.pixelAlign(
        sourceFrame,
        in: containerView
    )
    let pixelAlignedMenu = AetherGooeyGeometryCapture.pixelAlign(
        menuFrame,
        in: containerView
    )
    let resolvedPlacement = AetherGooeyGeometryCapture.resolvedPlacement(
        placement,
        source: pixelAlignedSource,
        menu: pixelAlignedMenu
    )
    let sourceRadius = sourceView.map {
        AetherGooeyGeometryCapture.sourceCornerRadius(
            for: $0,
            frame: pixelAlignedSource,
            policy: sourceCornerRadiusPolicy
        )
    } ?? min(pixelAlignedSource.width, pixelAlignedSource.height) * 0.5
    let menuRadius = AetherGooeyGeometryCapture.cornerRadius(
        for: menuView,
        frame: pixelAlignedMenu,
        policy: menuCornerRadiusPolicy
    )

    let sourceCenter = CGPoint(x: pixelAlignedSource.midX, y: pixelAlignedSource.midY)
    let menuCenter = CGPoint(x: pixelAlignedMenu.midX, y: pixelAlignedMenu.midY)
    let start = AetherGooeyGeometryCapture.edgePoint(
        rect: pixelAlignedSource,
        toward: pixelAlignedMenu,
        placement: resolvedPlacement
    )
    let end = AetherGooeyGeometryCapture.edgePoint(
        rect: pixelAlignedMenu,
        toward: pixelAlignedSource,
        placement: AetherGooeyGeometryCapture.opposite(resolvedPlacement)
    )

    return AetherGooeyGeometry(
        sourceFrameInContainer: pixelAlignedSource,
        menuFrameInContainer: pixelAlignedMenu,
        sourceCornerRadius: sourceRadius,
        menuCornerRadius: menuRadius,
        sourceCenter: sourceCenter,
        menuCenter: menuCenter,
        connectorStartPoint: start,
        connectorEndPoint: end,
        placement: resolvedPlacement,
        distance: AetherGooeyGeometryCapture.distanceBetween(
            source: pixelAlignedSource,
            menu: pixelAlignedMenu,
            placement: resolvedPlacement
        )
    )
}

private enum AetherGooeyGeometryCapture {
    static func convertedFrame(view: UIView, in containerView: UIView) -> CGRect {
        if let presentation = view.layer.presentation(),
           let superview = view.superview {
            let frame = superview.convert(presentation.frame, to: containerView)
            if isValid(frame) {
                return frame
            }
        }
        let frame = view.convert(view.bounds, to: containerView)
        guard isValid(frame) else {
            return CGRect(x: containerView.bounds.midX - 1.0, y: containerView.bounds.midY - 1.0, width: 2.0, height: 2.0)
        }
        return frame
    }

    static func fallbackSourceFrame(menuFrame: CGRect, placement: AetherContextMenuPlacement) -> CGRect {
        let side: CGFloat = 2.0
        let point: CGPoint
        switch placement {
        case .above:
            point = CGPoint(x: menuFrame.midX, y: menuFrame.maxY)
        case .below:
            point = CGPoint(x: menuFrame.midX, y: menuFrame.minY)
        case .leading:
            point = CGPoint(x: menuFrame.maxX, y: menuFrame.midY)
        case .trailing:
            point = CGPoint(x: menuFrame.minX, y: menuFrame.midY)
        case .overlapping:
            point = CGPoint(x: menuFrame.midX, y: menuFrame.midY)
        case let .custom(anchor):
            point = anchor
        }
        return CGRect(x: point.x - side * 0.5, y: point.y - side * 0.5, width: side, height: side)
    }

    static func pixelAlign(_ rect: CGRect, in view: UIView) -> CGRect {
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        guard scale > 0 else { return rect }
        let minX = floor(rect.minX * scale) / scale
        let minY = floor(rect.minY * scale) / scale
        let maxX = ceil(rect.maxX * scale) / scale
        let maxY = ceil(rect.maxY * scale) / scale
        return CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
    }

    static func cornerRadius(
        for view: UIView,
        frame: CGRect,
        policy: AetherGooeyCornerRadiusPolicy
    ) -> CGFloat {
        let maxRadius = min(frame.width, frame.height) * 0.5
        let radius: CGFloat
        switch policy {
        case let .fixed(value):
            radius = value
        case .fromLayer:
            radius = view.layer.cornerRadius
        case .fromPresentationLayer:
            radius = view.layer.presentation()?.cornerRadius ?? view.layer.cornerRadius
        case .capsule:
            radius = maxRadius
        }
        return AetherGooeyMath.clamp(radius, 0.0, maxRadius)
    }

    static func sourceCornerRadius(
        for view: UIView,
        frame: CGRect,
        policy: AetherGooeyCornerRadiusPolicy
    ) -> CGFloat {
        let radius = cornerRadius(for: view, frame: frame, policy: policy)
        let maxRadius = min(frame.width, frame.height) * 0.5
        guard maxRadius > 0.0 else { return 0.0 }

        switch policy {
        case .fromLayer, .fromPresentationLayer:
            if radius <= 0.5, min(frame.width, frame.height) <= 96.0 {
                return maxRadius
            }
        case .fixed, .capsule:
            break
        }
        return radius
    }

    static func resolvedPlacement(
        _ placement: AetherContextMenuPlacement,
        source: CGRect,
        menu: CGRect
    ) -> AetherContextMenuPlacement {
        switch placement {
        case .custom, .overlapping:
            return inferPlacement(source: source, menu: menu)
        default:
            return placement
        }
    }

    static func inferPlacement(source: CGRect, menu: CGRect) -> AetherContextMenuPlacement {
        if menu.minY >= source.maxY { return .below }
        if menu.maxY <= source.minY { return .above }
        if menu.minX >= source.maxX { return .trailing }
        if menu.maxX <= source.minX { return .leading }
        let dx = menu.midX - source.midX
        let dy = menu.midY - source.midY
        if abs(dy) >= abs(dx) {
            return dy >= 0.0 ? .below : .above
        }
        return dx >= 0.0 ? .trailing : .leading
    }

    static func opposite(_ placement: AetherContextMenuPlacement) -> AetherContextMenuPlacement {
        switch placement {
        case .above: return .below
        case .below: return .above
        case .leading: return .trailing
        case .trailing: return .leading
        case .overlapping, .custom: return .overlapping
        }
    }

    static func edgePoint(
        rect: CGRect,
        toward other: CGRect,
        placement: AetherContextMenuPlacement
    ) -> CGPoint {
        switch placement {
        case .above:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .below:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .leading:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .trailing:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .overlapping:
            return CGPoint(x: rect.midX, y: rect.midY)
        case let .custom(anchor):
            return anchor
        }
    }

    static func distanceBetween(
        source: CGRect,
        menu: CGRect,
        placement: AetherContextMenuPlacement
    ) -> CGFloat {
        switch placement {
        case .above:
            return max(0.0, source.minY - menu.maxY)
        case .below:
            return max(0.0, menu.minY - source.maxY)
        case .leading:
            return max(0.0, source.minX - menu.maxX)
        case .trailing:
            return max(0.0, menu.minX - source.maxX)
        case .overlapping, .custom:
            return hypot(menu.midX - source.midX, menu.midY - source.midY)
        }
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0.0
            && frame.height > 0.0
    }
}

// MARK: - Overlay

final class AetherGooeyTransitionOverlayView: UIView {
    let morphSurfaceView = AetherGooeyMorphSurfaceView()
    let debugView: AetherGooeyDebugView?
    var currentPath: CGPath? {
        morphSurfaceView.currentPath
    }

    init(
        configuration: AetherGooeyContextMenuTransitionConfiguration,
        isDark: Bool
    ) {
        self.debugView = configuration.debugShowsControlPoints ? AetherGooeyDebugView() : nil
        super.init(frame: .zero)

        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        addSubview(morphSurfaceView)

        if let debugView {
            addSubview(debugView)
        }
    }

    func setMenuPreviewImage(_ image: UIImage?) {
        morphSurfaceView.setContentImage(image)
    }

    func setSourcePreviewImage(_ image: UIImage?) {
        morphSurfaceView.setSourceImage(image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        morphSurfaceView.frame = bounds
        debugView?.frame = bounds
    }

    func update(
        geometry: AetherGooeyGeometry,
        progress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        configuration: AetherGooeyContextMenuTransitionConfiguration
    ) {
        let settings = AetherGooeyAccessibilitySettings.current
        let effectiveProgress = AetherGooeyMath.clamp(progress, 0.0, 1.0)

        morphSurfaceView.update(
            geometry: geometry,
            progress: effectiveProgress,
            phase: phase,
            configuration: configuration,
            accessibilitySettings: settings
        )
        debugView?.update(
            geometry: geometry,
            progress: effectiveProgress,
            phase: phase,
            connectorPath: morphSurfaceView.currentPath
        )
    }
}

fileprivate struct AetherGooeyMetaballUniforms {
    var viewportSizeAndAlpha: SIMD4<Float>
    var sourceRect: SIMD4<Float>
    var menuRect: SIMD4<Float>
    var contentRect: SIMD4<Float>
    var lensControls: SIMD4<Float>
    var bridgePoints: SIMD4<Float>
    var radiiAndTime: SIMD4<Float>
    var fillColor: SIMD4<Float>
    var edgeColor: SIMD4<Float>
    var targetControls: SIMD4<Float>
}

struct AetherGooeyMorphBodyFrame {
    var path: CGPath
    var sourceRect: CGRect
    var menuRect: CGRect
    var contentRect: CGRect
    var bridgeStart: CGPoint
    var bridgeEnd: CGPoint
    var sourceRadius: CGFloat
    var menuRadius: CGFloat
    var bridgeRadius: CGFloat
    var shapeProgress: CGFloat
    var targetMenuRadius: CGFloat

    static func interpolated(
        from current: AetherGooeyMorphBodyFrame,
        to target: AetherGooeyMorphBodyFrame,
        progress: CGFloat
    ) -> AetherGooeyMorphBodyFrame {
        let t = AetherGooeyMath.clamp(progress, 0.0, 1.0)
        let hasCurrentTail = current.sourceRadius > 0.1
        let hasTargetTail = target.sourceRadius > 0.1
        let sourceRect = hasCurrentTail && hasTargetTail
            ? interpolate(current.sourceRect, target.sourceRect, t)
            : target.sourceRect
        let sourceRadius = hasCurrentTail && hasTargetTail
            ? AetherGooeyMath.lerp(current.sourceRadius, target.sourceRadius, t)
            : target.sourceRadius
        let menuRect = interpolate(current.menuRect, target.menuRect, t)
        let menuRadius = AetherGooeyMath.lerp(current.menuRadius, target.menuRadius, t)
        let bridgeStart = AetherGooeyMath.lerpPoint(current.bridgeStart, target.bridgeStart, t)
        let bridgeEnd = AetherGooeyMath.lerpPoint(current.bridgeEnd, target.bridgeEnd, t)
        let bridgeRadius = AetherGooeyMath.lerp(current.bridgeRadius, target.bridgeRadius, t)

        return AetherGooeyMorphBodyFrame(
            path: makePath(
                sourceRect: sourceRect,
                menuRect: menuRect,
                bridgeStart: bridgeStart,
                bridgeEnd: bridgeEnd,
                sourceRadius: sourceRadius,
                menuRadius: menuRadius,
                bridgeRadius: bridgeRadius
            ),
            sourceRect: sourceRect,
            menuRect: menuRect,
            contentRect: interpolate(current.contentRect, target.contentRect, t),
            bridgeStart: bridgeStart,
            bridgeEnd: bridgeEnd,
            sourceRadius: sourceRadius,
            menuRadius: menuRadius,
            bridgeRadius: bridgeRadius,
            shapeProgress: AetherGooeyMath.lerp(current.shapeProgress, target.shapeProgress, t),
            targetMenuRadius: AetherGooeyMath.lerp(current.targetMenuRadius, target.targetMenuRadius, t)
        )
    }

    static func makePath(
        sourceRect: CGRect,
        menuRect: CGRect,
        bridgeStart: CGPoint,
        bridgeEnd: CGPoint,
        sourceRadius: CGFloat,
        menuRadius: CGFloat,
        bridgeRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        if sourceRadius > 0.1, sourceRect.width > 0.5, sourceRect.height > 0.5 {
            path.addPath(CGPath(
                roundedRect: sourceRect,
                cornerWidth: sourceRadius,
                cornerHeight: sourceRadius,
                transform: nil
            ))
        }

        let bridgeDistance = hypot(bridgeEnd.x - bridgeStart.x, bridgeEnd.y - bridgeStart.y)
        if bridgeRadius > 0.5, bridgeDistance > 1.0 {
            let line = CGMutablePath()
            line.move(to: bridgeStart)
            line.addLine(to: bridgeEnd)
            path.addPath(line.copy(
                strokingWithWidth: bridgeRadius * 2.0,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 0.0
            ))
        }

        if menuRect.width > 0.5, menuRect.height > 0.5 {
            path.addPath(CGPath(
                roundedRect: menuRect,
                cornerWidth: menuRadius,
                cornerHeight: menuRadius,
                transform: nil
            ))
        }
        return path
    }

    private static func interpolate(_ from: CGRect, _ to: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: AetherGooeyMath.lerp(from.minX, to.minX, progress),
            y: AetherGooeyMath.lerp(from.minY, to.minY, progress),
            width: AetherGooeyMath.lerp(from.width, to.width, progress),
            height: AetherGooeyMath.lerp(from.height, to.height, progress)
        )
    }
}

final class AetherGooeySDFSurfaceView: UIView {
    private let shadowLayer = CAShapeLayer()
    private let materialLayer = CAShapeLayer()
    private let edgeLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        [shadowLayer, materialLayer, edgeLayer, highlightLayer].forEach(configure)
        shadowLayer.fillColor = UIColor.black.cgColor
        materialLayer.lineWidth = 0.0
        edgeLayer.fillColor = UIColor.clear.cgColor
        highlightLayer.strokeColor = UIColor.clear.cgColor

        layer.addSublayer(shadowLayer)
        layer.addSublayer(materialLayer)
        layer.addSublayer(edgeLayer)
        layer.addSublayer(highlightLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        [shadowLayer, materialLayer, edgeLayer, highlightLayer].forEach {
            $0.frame = bounds
        }
    }

    func update(
        bodyFrame: AetherGooeyMorphBodyFrame,
        alpha: CGFloat,
        fillColor: UIColor,
        edgeColor: UIColor,
        configuration: AetherGooeyContextMenuTransitionConfiguration,
        settings: AetherGooeyAccessibilitySettings
    ) {
        let clampedAlpha = AetherGooeyMath.clamp(alpha, 0.0, 1.0)
        let path = bodyFrame.path
        let bridgeEnergy = AetherGooeyMath.clamp(
            bodyFrame.bridgeRadius / max(1.0, configuration.connectorMaximumThickness * 0.42),
            0.0,
            1.0
        )
        let surfaceAlpha = settings.reduceTransparency
            ? min(0.86, clampedAlpha * 0.74)
            : min(0.78, clampedAlpha * (0.62 + bridgeEnergy * 0.08))
        let shadowOpacity = Float(clampedAlpha * (settings.increasedContrast ? 0.12 : 0.085))
        let edgeOpacity = Float(clampedAlpha * (settings.increasedContrast ? 0.22 : 0.12))
        let highlightOpacity = Float(clampedAlpha * (settings.reduceMotion ? 0.04 : 0.07))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer.shadowPath = path
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = shadowOpacity
        layer.shadowRadius = 16.0 + bridgeEnergy * 5.0
        layer.shadowOffset = CGSize(width: 0.0, height: 8.0)

        shadowLayer.path = path
        shadowLayer.opacity = 0.0

        materialLayer.path = path
        materialLayer.fillColor = fillColor.withAlphaComponent(surfaceAlpha).cgColor
        materialLayer.opacity = Float(clampedAlpha)

        edgeLayer.path = path
        edgeLayer.strokeColor = edgeColor.cgColor
        edgeLayer.lineWidth = 1.0 / max(1.0, window?.screen.scale ?? UIScreen.main.scale)
        edgeLayer.opacity = edgeOpacity

        highlightLayer.path = path
        highlightLayer.fillColor = UIColor.white.withAlphaComponent(0.055).cgColor
        highlightLayer.opacity = highlightOpacity

        CATransaction.commit()
    }

    private func configure(_ layer: CAShapeLayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.allowsEdgeAntialiasing = true
        layer.fillRule = .nonZero
        layer.lineJoin = .round
        layer.lineCap = .round
        layer.rasterizationScale = UIScreen.main.scale
        layer.shouldRasterize = true
    }
}

final class AetherGooeyMorphSurfaceView: UIView {
    private let shaderView = AetherGooeyMetaballShaderView()
    private let sdfSurfaceView = AetherGooeySDFSurfaceView()
    private let bodyLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    var rendersVisibleSurface = true
    private(set) var currentPath: CGPath?
    private(set) var currentBodyFrame: AetherGooeyMorphBodyFrame?
    private(set) var currentAlpha: CGFloat = 0.0
    private var displayedBodyFrame: AetherGooeyMorphBodyFrame?
    private var lastPhase: AetherGooeyTransitionPhase?
    private var lastShapeProgress: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        configureBody(layer: bodyLayer)
        configureHighlight(layer: highlightLayer)
        shaderView.isHidden = true
        addSubview(shaderView)
        addSubview(sdfSurfaceView)
        self.layer.addSublayer(bodyLayer)
        self.layer.addSublayer(highlightLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shaderView.frame = bounds
        sdfSurfaceView.frame = bounds
        bodyLayer.frame = bounds
        highlightLayer.frame = bounds
    }

    func setContentImage(_ image: UIImage?) {
        shaderView.setContentImage(image)
    }

    func setSourceImage(_ image: UIImage?) {
        shaderView.setSourceImage(image)
    }

    func update(
        geometry: AetherGooeyGeometry,
        progress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        configuration: AetherGooeyContextMenuTransitionConfiguration,
        accessibilitySettings: AetherGooeyAccessibilitySettings
    ) {
        let t = AetherGooeyMath.clamp(progress, 0.0, 1.0)
        let shapeT = phase == .opening ? t : 1.0 - t
        let targetBodyFrame = Self.makeBodyFrame(
            geometry: geometry,
            shapeProgress: shapeT,
            configuration: configuration,
            accessibilitySettings: accessibilitySettings
        )
        let bodyFrame = smoothedBodyFrame(
            target: targetBodyFrame,
            shapeProgress: shapeT,
            phase: phase,
            reduceMotion: accessibilitySettings.reduceMotion
        )
        let path = bodyFrame.path
        currentPath = path
        currentBodyFrame = bodyFrame

        let alpha: CGFloat = {
            switch phase {
            case .opening:
                return 1.0 - AetherGooeyMath.smootherstep(0.94, 1.0, t)
            case .closing:
                return 1.0 - AetherGooeyMath.smootherstep(0.90, 1.0, t)
            }
        }()
        currentAlpha = alpha

        let fillColor = materialColor(
            configuration: configuration,
            settings: accessibilitySettings
        )
        let edgeColor = shaderEdgeColor(settings: accessibilitySettings)
        sdfSurfaceView.update(
            bodyFrame: bodyFrame,
            alpha: alpha,
            fillColor: fillColor,
            edgeColor: edgeColor,
            configuration: configuration,
            settings: accessibilitySettings
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sdfSurfaceView.isHidden = !rendersVisibleSurface || alpha <= 0.001
        bodyLayer.isHidden = true
        bodyLayer.path = path
        bodyLayer.fillColor = fillColor.cgColor
        bodyLayer.opacity = Float(alpha)

        highlightLayer.path = path
        highlightLayer.fillColor = UIColor.clear.cgColor
        highlightLayer.strokeColor = UIColor.clear.cgColor
        highlightLayer.opacity = 0.0
        CATransaction.commit()
    }

    private func smoothedBodyFrame(
        target: AetherGooeyMorphBodyFrame,
        shapeProgress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        reduceMotion: Bool
    ) -> AetherGooeyMorphBodyFrame {
        defer {
            lastPhase = phase
            lastShapeProgress = shapeProgress
        }

        guard !reduceMotion,
              let previous = displayedBodyFrame,
              lastPhase == phase,
              let lastShapeProgress else {
            displayedBodyFrame = target
            return target
        }

        let delta = abs(shapeProgress - lastShapeProgress)
        let isEndpoint = shapeProgress <= 0.002 || shapeProgress >= 0.998
        let isSeek = delta > 0.16
        guard !isEndpoint, !isSeek else {
            displayedBodyFrame = target
            return target
        }

        let blend = AetherGooeyMath.clamp(0.32 + delta * 6.0, 0.32, 0.68)
        let smoothed = AetherGooeyMorphBodyFrame.interpolated(
            from: previous,
            to: target,
            progress: blend
        )
        displayedBodyFrame = smoothed
        return smoothed
    }

    private static func makeBodyFrame(
        geometry: AetherGooeyGeometry,
        shapeProgress: CGFloat,
        configuration: AetherGooeyContextMenuTransitionConfiguration,
        accessibilitySettings: AetherGooeyAccessibilitySettings
    ) -> AetherGooeyMorphBodyFrame {
        let t = AetherGooeyMath.clamp(shapeProgress, 0.0, 1.0)
        let path = CGMutablePath()
        let pullT = accessibilitySettings.reduceMotion ? t : AetherGooeyMath.smootherstep(0.02, 0.82, t)
        let growT = accessibilitySettings.reduceMotion ? t : AetherGooeyMath.smootherstep(0.04, 0.92, t)
        let tailT = accessibilitySettings.reduceMotion
            ? max(0.0, 1.0 - t)
            : 1.0 - AetherGooeyMath.smootherstep(0.035, 0.30, t)
        let liquidT = accessibilitySettings.reduceMotion ? 0.0 : sin(.pi * t)

        var bodyCenter = AetherGooeyMath.lerpPoint(
            geometry.sourceCenter,
            geometry.menuCenter,
            pullT
        )
        if !accessibilitySettings.reduceMotion {
            let travel = CGPoint(
                x: geometry.menuCenter.x - geometry.sourceCenter.x,
                y: geometry.menuCenter.y - geometry.sourceCenter.y
            )
            let distance = max(1.0, hypot(travel.x, travel.y))
            let normal = CGPoint(x: -travel.y / distance, y: travel.x / distance)
            let arc = min(18.0, distance * 0.045) * sin(.pi * t) * (1.0 - AetherGooeyMath.smootherstep(0.84, 1.0, t))
            bodyCenter.x += normal.x * arc
            bodyCenter.y += normal.y * arc
        }
        let pulse = accessibilitySettings.reduceMotion
            ? 0.0
            : sin(.pi * t) * 0.032 + sin(.pi * 2.0 * t) * 0.010
        let bodyWidth = AetherGooeyMath.lerp(
            max(geometry.sourceFrameInContainer.width, geometry.sourceFrameInContainer.width * 1.08),
            geometry.menuFrameInContainer.width,
            growT
        ) * (1.0 + liquidT * 0.026 + pulse)
        let bodyHeight = AetherGooeyMath.lerp(
            max(geometry.sourceFrameInContainer.height, geometry.sourceFrameInContainer.height * 1.08),
            geometry.menuFrameInContainer.height,
            growT
        ) * (1.0 - liquidT * 0.014 + pulse * 0.34)

        let projectedBodyRect = CGRect(
            x: bodyCenter.x - bodyWidth * 0.5,
            y: bodyCenter.y - bodyHeight * 0.5,
            width: bodyWidth,
            height: bodyHeight
        )
        let bodyRect = interpolate(
            projectedBodyRect,
            to: geometry.menuFrameInContainer,
            progress: AetherGooeyMath.smootherstep(0.66, 1.0, t)
        )
        let tailScale = AetherGooeyMath.lerp(1.0, 0.018, AetherGooeyMath.smootherstep(0.035, 0.34, t))
        let tailWidth = max(1.0, geometry.sourceFrameInContainer.width * tailScale)
        let tailHeight = max(1.0, geometry.sourceFrameInContainer.height * tailScale)
        let tailRect = CGRect(
            x: geometry.sourceCenter.x - tailWidth * 0.5,
            y: geometry.sourceCenter.y - tailHeight * 0.5,
            width: tailWidth,
            height: tailHeight
        )
        let finalMenuRadius = min(
            geometry.menuCornerRadius,
            min(bodyRect.width, bodyRect.height) * 0.5
        )
        let capsuleRadius = min(bodyRect.width, bodyRect.height) * 0.5
        let radiusSettleT = AetherGooeyMath.smootherstep(0.54, 1.0, t)
        let bodyRadius = max(
            finalMenuRadius,
            AetherGooeyMath.lerp(capsuleRadius, finalMenuRadius, radiusSettleT)
        )
        let tailRadius = min(
            geometry.sourceCornerRadius * tailScale,
            min(tailRect.width, tailRect.height) * 0.5
        )
        let bridgeStart = AetherGooeyGeometryCapture.edgePoint(
            rect: tailRect,
            toward: bodyRect,
            placement: geometry.placement
        )
        let bridgeEnd = AetherGooeyGeometryCapture.edgePoint(
            rect: bodyRect,
            toward: tailRect,
            placement: AetherGooeyGeometryCapture.opposite(geometry.placement)
        )
        let bridgeDistance = hypot(bridgeEnd.x - bridgeStart.x, bridgeEnd.y - bridgeStart.y)
        let bridgeT = accessibilitySettings.reduceMotion
            ? 0.0
            : AetherGooeyMath.smootherstep(0.015, 0.12, t)
                * (1.0 - AetherGooeyMath.smootherstep(0.18, 0.40, t))
        let bridgeRadius = min(
            configuration.connectorMaximumThickness * 0.58,
            min(min(tailRect.width, tailRect.height), min(bodyRect.width, bodyRect.height)) * 0.42
        ) * bridgeT

        if tailT > 0.02, tailRect.width > 0.5, tailRect.height > 0.5 {
            path.addPath(roundedPath(
                rect: tailRect,
                radius: tailRadius
            ))
        }
        if bridgeRadius > 0.5, bridgeDistance > 1.0 {
            path.addPath(capsulePath(
                from: bridgeStart,
                to: bridgeEnd,
                radius: bridgeRadius
            ))
        }
        if bodyRect.width > 0.5, bodyRect.height > 0.5 {
            path.addPath(roundedPath(
                rect: bodyRect,
                radius: bodyRadius
            ))
        }

        let shaderTailRect = tailT > 0.02
            ? tailRect
            : CGRect(x: -10_000.0, y: -10_000.0, width: 1.0, height: 1.0)

        return AetherGooeyMorphBodyFrame(
            path: path,
            sourceRect: shaderTailRect,
            menuRect: bodyRect,
            contentRect: geometry.menuFrameInContainer,
            bridgeStart: bridgeStart,
            bridgeEnd: bridgeEnd,
            sourceRadius: tailT > 0.02 ? tailRadius : 0.0,
            menuRadius: bodyRadius,
            bridgeRadius: bridgeRadius,
            shapeProgress: t,
            targetMenuRadius: geometry.menuCornerRadius
        )
    }

    private static func revealedMenuFrame(
        source: CGRect,
        menu: CGRect,
        placement: AetherContextMenuPlacement,
        progress: CGFloat
    ) -> CGRect {
        let t = AetherGooeyMath.clamp(progress, 0.0, 1.0)
        let minWidth = min(menu.width, max(source.width * 1.18, menu.width * 0.34))
        let minHeight = min(menu.height, max(source.height * 1.12, menu.height * 0.24))
        let width = AetherGooeyMath.lerp(minWidth, menu.width, t)
        let height = AetherGooeyMath.lerp(minHeight, menu.height, t)
        let centerX = AetherGooeyMath.lerp(source.midX, menu.midX, AetherGooeyMath.smootherstep(0.10, 0.78, t))
        let centerY = AetherGooeyMath.lerp(source.midY, menu.midY, AetherGooeyMath.smootherstep(0.10, 0.78, t))

        switch placement {
        case .below:
            return CGRect(x: centerX - width * 0.5, y: menu.minY, width: width, height: height)
        case .above:
            return CGRect(x: centerX - width * 0.5, y: menu.maxY - height, width: width, height: height)
        case .trailing:
            return CGRect(x: menu.minX, y: centerY - height * 0.5, width: width, height: height)
        case .leading:
            return CGRect(x: menu.maxX - width, y: centerY - height * 0.5, width: width, height: height)
        case .overlapping, .custom:
            return CGRect(x: centerX - width * 0.5, y: centerY - height * 0.5, width: width, height: height)
        }
    }

    private static func scale(
        _ rect: CGRect,
        around center: CGPoint,
        x scaleX: CGFloat,
        y scaleY: CGFloat
    ) -> CGRect {
        let width = rect.width * scaleX
        let height = rect.height * scaleY
        return CGRect(
            x: center.x - width * 0.5,
            y: center.y - height * 0.5,
            width: width,
            height: height
        )
    }

    private static func roundedPath(rect: CGRect, radius: CGFloat) -> CGPath {
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: max(0.0, min(radius, min(rect.width, rect.height) * 0.5))
        ).cgPath
    }

    private static func interpolate(
        _ rect: CGRect,
        to target: CGRect,
        progress: CGFloat
    ) -> CGRect {
        let t = AetherGooeyMath.clamp(progress, 0.0, 1.0)
        return CGRect(
            x: AetherGooeyMath.lerp(rect.minX, target.minX, t),
            y: AetherGooeyMath.lerp(rect.minY, target.minY, t),
            width: AetherGooeyMath.lerp(rect.width, target.width, t),
            height: AetherGooeyMath.lerp(rect.height, target.height, t)
        )
    }

    private static func capsulePath(
        from start: CGPoint,
        to end: CGPoint,
        radius: CGFloat
    ) -> CGPath {
        let line = CGMutablePath()
        line.move(to: start)
        line.addLine(to: end)
        return line.copy(
            strokingWithWidth: radius * 2.0,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0.0
        )
    }

    private func makeShaderUniforms(
        bodyFrame: AetherGooeyMorphBodyFrame,
        alpha: CGFloat,
        progress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        fillColor: UIColor,
        edgeColor: UIColor,
        configuration: AetherGooeyContextMenuTransitionConfiguration,
        settings: AetherGooeyAccessibilitySettings
    ) -> AetherGooeyMetaballUniforms {
        let smoothness = settings.reduceMotion
            ? 2.0
            : max(12.0, configuration.connectorMaximumThickness * 0.62)
        let contentAlpha: CGFloat
        let blurRadius: CGFloat
        let warp: CGFloat
        switch phase {
        case .opening:
            contentAlpha = 1.0
            blurRadius = AetherGooeyMath.lerp(9.0, 0.55, AetherGooeyMath.smootherstep(0.12, 0.98, progress))
            warp = (1.0 - AetherGooeyMath.smootherstep(0.86, 1.0, progress)) * 0.78
        case .closing:
            contentAlpha = 1.0
            blurRadius = AetherGooeyMath.lerp(0.55, 10.0, AetherGooeyMath.smootherstep(0.18, 1.0, progress))
            warp = (1.0 - AetherGooeyMath.smootherstep(0.78, 1.0, progress)) * 0.88
        }
        return AetherGooeyMetaballUniforms(
            viewportSizeAndAlpha: SIMD4<Float>(
                Float(max(1.0, bounds.width)),
                Float(max(1.0, bounds.height)),
                Float(AetherGooeyMath.clamp(alpha, 0.0, 1.0)),
                Float(smoothness)
            ),
            sourceRect: SIMD4<Float>(
                Float(bodyFrame.sourceRect.minX),
                Float(bodyFrame.sourceRect.minY),
                Float(max(0.0, bodyFrame.sourceRect.width)),
                Float(max(0.0, bodyFrame.sourceRect.height))
            ),
            menuRect: SIMD4<Float>(
                Float(bodyFrame.menuRect.minX),
                Float(bodyFrame.menuRect.minY),
                Float(max(0.0, bodyFrame.menuRect.width)),
                Float(max(0.0, bodyFrame.menuRect.height))
            ),
            contentRect: SIMD4<Float>(
                Float(bodyFrame.contentRect.minX),
                Float(bodyFrame.contentRect.minY),
                Float(max(1.0, bodyFrame.contentRect.width)),
                Float(max(1.0, bodyFrame.contentRect.height))
            ),
            lensControls: SIMD4<Float>(
                Float(AetherGooeyMath.clamp(progress, 0.0, 1.0)),
                Float(AetherGooeyMath.clamp(contentAlpha, 0.0, 1.0)),
                Float(max(0.0, blurRadius)),
                Float(max(0.0, warp))
            ),
            bridgePoints: SIMD4<Float>(
                Float(bodyFrame.bridgeStart.x),
                Float(bodyFrame.bridgeStart.y),
                Float(bodyFrame.bridgeEnd.x),
                Float(bodyFrame.bridgeEnd.y)
            ),
            radiiAndTime: SIMD4<Float>(
                Float(max(0.0, bodyFrame.sourceRadius)),
                Float(max(0.0, bodyFrame.menuRadius)),
                Float(max(0.0, bodyFrame.bridgeRadius)),
                Float(bodyFrame.shapeProgress)
            ),
            fillColor: rgbaComponents(fillColor),
            edgeColor: rgbaComponents(edgeColor),
            targetControls: SIMD4<Float>(
                Float(max(0.0, bodyFrame.targetMenuRadius)),
                phase == .opening ? 1.0 : 0.0,
                0.0,
                0.0
            )
        )
    }

    private func configureBody(layer: CAShapeLayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.allowsEdgeAntialiasing = true
        layer.fillRule = .nonZero
        layer.strokeColor = UIColor.clear.cgColor
        layer.lineWidth = 0.0
    }

    private func configureHighlight(layer: CAShapeLayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.allowsEdgeAntialiasing = true
        layer.fillRule = .nonZero
        layer.fillColor = UIColor.white.withAlphaComponent(0.10).cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.16).cgColor
        layer.lineWidth = 1.0 / UIScreen.main.scale
    }

    private func materialColor(
        configuration: AetherGooeyContextMenuTransitionConfiguration,
        settings: AetherGooeyAccessibilitySettings
    ) -> UIColor {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let base = isDark ? UIColor(white: 1.0, alpha: 1.0) : UIColor.white
        let alphaBoost: CGFloat = settings.reduceTransparency ? 1.75 : 1.0
        let baseAlpha = max(configuration.tintAlpha, isDark ? 0.30 : 0.38)
        return base.withAlphaComponent(
            AetherGooeyMath.clamp(baseAlpha * alphaBoost, 0.0, 0.68)
        )
    }

    private func shaderEdgeColor(settings: AetherGooeyAccessibilitySettings) -> UIColor {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let alpha: CGFloat = settings.increasedContrast ? 0.22 : 0.14
        if isDark {
            return UIColor(white: 1.0, alpha: settings.increasedContrast ? 0.28 : 0.18)
        }
        return UIColor(white: 0.0, alpha: alpha)
    }

    private func rgbaComponents(_ color: UIColor) -> SIMD4<Float> {
        let resolved = color.resolvedColor(with: traitCollection)
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
        }

        var white: CGFloat = 0.0
        if resolved.getWhite(&white, alpha: &alpha) {
            return SIMD4<Float>(Float(white), Float(white), Float(white), Float(alpha))
        }

        return SIMD4<Float>(1.0, 1.0, 1.0, Float(alpha))
    }
}

final class AetherGooeyMetaballShaderView: UIView {
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    private let metalDevice: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let renderPSO: MTLRenderPipelineState?
    private let textureLoader: MTKTextureLoader?
    private let transparentTexture: MTLTexture?
    private var sourceTexture: MTLTexture?
    private var contentTexture: MTLTexture?

    let isReady: Bool

    override init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        let queue = device?.makeCommandQueue()
        let library: MTLLibrary? = {
            guard let device else { return nil }
            if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
                return library
            }
            return device.makeDefaultLibrary()
        }()
        let vertexFn = library?.makeFunction(name: "gooeyMetaballVertex")
        let fragmentFn = library?.makeFunction(name: "gooeyMetaballFragment")
        let renderPSO: MTLRenderPipelineState? = {
            guard let device, let vertexFn, let fragmentFn else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = false
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }()

        self.metalDevice = device
        self.commandQueue = queue
        self.renderPSO = renderPSO
        self.textureLoader = device.map { MTKTextureLoader(device: $0) }
        self.transparentTexture = Self.makeTransparentTexture(device: device)
        self.isReady = device != nil
            && queue != nil
            && library != nil
            && vertexFn != nil
            && fragmentFn != nil
            && renderPSO != nil

        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        let metalLayer = self.metalLayer
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.presentsWithTransaction = false

        if !isReady {
            NSLog("[AetherGooeyMetaballShaderView] Metal init failed - device=%@ queue=%@ library=%@ vertex=%@ fragment=%@ pso=%@",
                  String(describing: device != nil),
                  String(describing: queue != nil),
                  String(describing: library != nil),
                  String(describing: vertexFn != nil),
                  String(describing: fragmentFn != nil),
                  String(describing: renderPSO != nil))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    func setContentImage(_ image: UIImage?) {
        contentTexture = makeTexture(from: image)
    }

    func setSourceImage(_ image: UIImage?) {
        sourceTexture = makeTexture(from: image)
    }

    private func makeTexture(from image: UIImage?) -> MTLTexture? {
        guard let image,
              let cgImage = image.cgImage,
              let textureLoader else {
            return nil
        }
        return try? textureLoader.newTexture(
            cgImage: cgImage,
            options: [
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.topLeft
            ]
        )
    }

    @discardableResult
    fileprivate func render(uniforms: AetherGooeyMetaballUniforms) -> Bool {
        guard isReady,
              bounds.width > 1.0,
              bounds.height > 1.0,
              let commandQueue,
              let renderPSO else {
            return false
        }

        updateDrawableSize()
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return false
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }

        var uniforms = uniforms
        encoder.setRenderPipelineState(renderPSO)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<AetherGooeyMetaballUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AetherGooeyMetaballUniforms>.stride, index: 0)
        encoder.setFragmentTexture(contentTexture ?? transparentTexture, index: 0)
        encoder.setFragmentTexture(sourceTexture ?? transparentTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    private func updateDrawableSize() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        let width = max(1.0, bounds.width * scale)
        let height = max(1.0, bounds.height * scale)
        let drawableSize = CGSize(width: width, height: height)
        if metalLayer.drawableSize != drawableSize {
            metalLayer.drawableSize = drawableSize
        }
    }

    private static func makeTransparentTexture(device: MTLDevice?) -> MTLTexture? {
        guard let device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        var pixel: UInt32 = 0
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )
        return texture
    }
}

final class AetherGooeyConnectorView: UIView {
    private let materialLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private(set) var currentPath: CGPath?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        Self.configure(materialLayer)
        Self.configure(strokeLayer)
        Self.configure(highlightLayer)
        layer.addSublayer(materialLayer)
        layer.addSublayer(strokeLayer)
        layer.addSublayer(highlightLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        materialLayer.frame = bounds
        strokeLayer.frame = bounds
        highlightLayer.frame = bounds
    }

    func update(
        geometry: AetherGooeyGeometry,
        progress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        configuration: AetherGooeyContextMenuTransitionConfiguration
    ) {
        let path = Self.makeConnectorPath(
            source: geometry.sourceFrameInContainer,
            menu: geometry.menuFrameInContainer,
            placement: geometry.placement,
            progress: progress,
            minThickness: configuration.connectorMinimumThickness,
            maxThickness: configuration.connectorMaximumThickness,
            maxConnectorLength: configuration.connectorMaximumLength
        )
        currentPath = path

        let settings = AetherGooeyAccessibilitySettings.current
        let alpha = Self.connectorAlpha(
            progress: progress,
            phase: phase,
            distance: geometry.distance,
            maxLength: configuration.connectorMaximumLength,
            settings: settings
        )
        let fillAlpha = configuration.tintAlpha * (settings.reduceTransparency ? 1.8 : 1.0)
        let strokeAlpha = configuration.strokeAlpha * (settings.increasedContrast ? 1.45 : 1.0)
        let isDark = traitCollection.userInterfaceStyle == .dark
        let fillColor = (isDark ? UIColor(white: 1.0, alpha: 1.0) : UIColor.white)
            .withAlphaComponent(AetherGooeyMath.clamp(fillAlpha, 0.0, 0.65))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        materialLayer.path = path
        materialLayer.fillColor = fillColor.cgColor
        materialLayer.opacity = Float(alpha)

        strokeLayer.path = path
        strokeLayer.strokeColor = UIColor.white.withAlphaComponent(AetherGooeyMath.clamp(strokeAlpha, 0.0, 0.75)).cgColor
        strokeLayer.opacity = Float(alpha)

        highlightLayer.path = path
        highlightLayer.fillColor = UIColor.white.withAlphaComponent(configuration.highlightAlpha * 0.34).cgColor
        highlightLayer.opacity = Float(alpha * (settings.reduceMotion ? 0.35 : 1.0))
        CATransaction.commit()
    }

    static func makeConnectorPath(
        source: CGRect,
        menu: CGRect,
        placement: AetherContextMenuPlacement,
        progress: CGFloat,
        minThickness: CGFloat,
        maxThickness: CGFloat,
        maxConnectorLength: CGFloat
    ) -> CGPath {
        let t = AetherGooeyMath.clamp(progress, 0.0, 1.0)
        guard t > 0.001, source.width > 0.0, source.height > 0.0, menu.width > 0.0, menu.height > 0.0 else {
            return CGMutablePath()
        }

        let resolvedPlacement = AetherGooeyGeometryCapture.resolvedPlacement(placement, source: source, menu: menu)
        let distance = AetherGooeyGeometryCapture.distanceBetween(
            source: source,
            menu: menu,
            placement: resolvedPlacement
        )
        let normalizedDistance = AetherGooeyMath.clamp(distance / max(1.0, maxConnectorLength), 0.0, 1.0)
        let growT = AetherGooeyMath.smootherstep(0.08, 0.55, t)
        let dissolveT = 1.0 - AetherGooeyMath.smootherstep(0.72, 1.0, t)
        let activeT = max(0.0, growT * max(0.18, dissolveT))
        let thickness = AetherGooeyMath.lerp(
            minThickness,
            maxThickness,
            activeT * (1.0 - normalizedDistance * 0.35)
        )
        let sourceSegment = attachmentSegment(
            on: source,
            side: sourceSide(for: resolvedPlacement),
            thickness: thickness * (0.72 + 0.28 * growT)
        )
        let targetSegment = attachmentSegment(
            on: menu,
            side: targetSide(for: resolvedPlacement),
            thickness: thickness * (0.58 + 0.52 * growT)
        )
        let tension = max(18.0, min(maxConnectorLength, distance + thickness * 1.35)) * (0.52 + 0.28 * growT)

        return cubicBridgePath(
            sourceA: sourceSegment.a,
            sourceB: sourceSegment.b,
            targetA: targetSegment.a,
            targetB: targetSegment.b,
            placement: resolvedPlacement,
            tension: tension
        )
    }

    private static func connectorAlpha(
        progress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        distance: CGFloat,
        maxLength: CGFloat,
        settings: AetherGooeyAccessibilitySettings
    ) -> CGFloat {
        if settings.reduceMotion {
            return 0.0
        }
        let normalizedDistance = AetherGooeyMath.clamp(distance / max(1.0, maxLength), 0.0, 1.0)
        switch phase {
        case .opening:
            let grow = AetherGooeyMath.smootherstep(0.08, 0.48, progress)
            let dissolve = 1.0 - AetherGooeyMath.smootherstep(0.62, 0.94, progress)
            return grow * dissolve * (1.0 - normalizedDistance * 0.35)
        case .closing:
            let appear = AetherGooeyMath.smootherstep(0.06, 0.42, progress)
            let retract = 1.0 - AetherGooeyMath.smootherstep(0.70, 0.98, progress)
            return appear * retract * (1.0 - normalizedDistance * 0.35)
        }
    }

    private static func configure(_ layer: CAShapeLayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.allowsEdgeAntialiasing = true
        layer.lineJoin = .round
        layer.lineCap = .round
        layer.lineWidth = 1.0 / UIScreen.main.scale
    }

    private enum EdgeSide {
        case top
        case bottom
        case left
        case right
    }

    private struct AttachmentSegment {
        var a: CGPoint
        var b: CGPoint
    }

    private static func sourceSide(for placement: AetherContextMenuPlacement) -> EdgeSide {
        switch placement {
        case .above: return .top
        case .below: return .bottom
        case .leading: return .left
        case .trailing: return .right
        case .overlapping, .custom:
            return .bottom
        }
    }

    private static func targetSide(for placement: AetherContextMenuPlacement) -> EdgeSide {
        switch placement {
        case .above: return .bottom
        case .below: return .top
        case .leading: return .right
        case .trailing: return .left
        case .overlapping, .custom:
            return .top
        }
    }

    private static func attachmentSegment(
        on rect: CGRect,
        side: EdgeSide,
        thickness: CGFloat
    ) -> AttachmentSegment {
        let half = max(1.0, thickness * 0.5)
        switch side {
        case .top:
            let clamped = min(half, rect.width * 0.42)
            return AttachmentSegment(
                a: CGPoint(x: rect.midX - clamped, y: rect.minY),
                b: CGPoint(x: rect.midX + clamped, y: rect.minY)
            )
        case .bottom:
            let clamped = min(half, rect.width * 0.42)
            return AttachmentSegment(
                a: CGPoint(x: rect.midX - clamped, y: rect.maxY),
                b: CGPoint(x: rect.midX + clamped, y: rect.maxY)
            )
        case .left:
            let clamped = min(half, rect.height * 0.42)
            return AttachmentSegment(
                a: CGPoint(x: rect.minX, y: rect.midY - clamped),
                b: CGPoint(x: rect.minX, y: rect.midY + clamped)
            )
        case .right:
            let clamped = min(half, rect.height * 0.42)
            return AttachmentSegment(
                a: CGPoint(x: rect.maxX, y: rect.midY - clamped),
                b: CGPoint(x: rect.maxX, y: rect.midY + clamped)
            )
        }
    }

    private static func cubicBridgePath(
        sourceA: CGPoint,
        sourceB: CGPoint,
        targetA: CGPoint,
        targetB: CGPoint,
        placement: AetherContextMenuPlacement,
        tension: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        let direction = directionVector(for: placement)
        let cpSource = CGPoint(x: direction.x * tension, y: direction.y * tension)
        let cpTarget = CGPoint(x: -direction.x * tension, y: -direction.y * tension)

        path.move(to: sourceA)
        path.addCurve(
            to: targetA,
            control1: CGPoint(x: sourceA.x + cpSource.x, y: sourceA.y + cpSource.y),
            control2: CGPoint(x: targetA.x + cpTarget.x, y: targetA.y + cpTarget.y)
        )
        path.addLine(to: targetB)
        path.addCurve(
            to: sourceB,
            control1: CGPoint(x: targetB.x + cpTarget.x, y: targetB.y + cpTarget.y),
            control2: CGPoint(x: sourceB.x + cpSource.x, y: sourceB.y + cpSource.y)
        )
        path.closeSubpath()
        return path
    }

    private static func directionVector(for placement: AetherContextMenuPlacement) -> CGPoint {
        switch placement {
        case .above: return CGPoint(x: 0.0, y: -1.0)
        case .below: return CGPoint(x: 0.0, y: 1.0)
        case .leading: return CGPoint(x: -1.0, y: 0.0)
        case .trailing: return CGPoint(x: 1.0, y: 0.0)
        case .overlapping, .custom: return CGPoint(x: 0.0, y: 1.0)
        }
    }
}

final class AetherGooeyDebugView: UIView {
    private let sourceLayer = CAShapeLayer()
    private let menuLayer = CAShapeLayer()
    private let connectorLayer = CAShapeLayer()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        configure(sourceLayer, color: .systemBlue)
        configure(menuLayer, color: .systemGreen)
        configure(connectorLayer, color: .systemPink)
        layer.addSublayer(sourceLayer)
        layer.addSublayer(menuLayer)
        layer.addSublayer(connectorLayer)
        label.font = .monospacedSystemFont(ofSize: 10.0, weight: .medium)
        label.textColor = .systemPink
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.numberOfLines = 3
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sourceLayer.frame = bounds
        menuLayer.frame = bounds
        connectorLayer.frame = bounds
    }

    func update(
        geometry: AetherGooeyGeometry,
        progress: CGFloat,
        phase: AetherGooeyTransitionPhase,
        connectorPath: CGPath?
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sourceLayer.path = UIBezierPath(rect: geometry.sourceFrameInContainer).cgPath
        menuLayer.path = UIBezierPath(rect: geometry.menuFrameInContainer).cgPath
        connectorLayer.path = connectorPath
        CATransaction.commit()
        label.text = "\(phase) \(String(format: "%.2f", progress))\nd=\(String(format: "%.1f", geometry.distance))"
        label.sizeToFit()
        label.frame = CGRect(
            x: geometry.sourceFrameInContainer.minX,
            y: max(0.0, geometry.sourceFrameInContainer.minY - label.bounds.height - 4.0),
            width: label.bounds.width + 8.0,
            height: label.bounds.height + 4.0
        )
    }

    private func configure(_ layer: CAShapeLayer, color: UIColor) {
        layer.contentsScale = UIScreen.main.scale
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = color.cgColor
        layer.lineDashPattern = [4, 3]
        layer.lineWidth = 1.0
    }
}

// MARK: - Animator

enum AetherGooeyTiming {
    case easeInOut
    case cubicBezier(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
    case spring(damping: CGFloat, response: CGFloat)
}

final class AetherGooeyAnimator {
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0.0
    private var duration: TimeInterval = 0.0
    private var timing: AetherGooeyTiming = .easeInOut
    private var update: ((CGFloat) -> Void)?
    private var completion: ((Bool) -> Void)?
    private var didComplete = false
    private(set) var frameCount: Int = 0

    func animate(
        duration: TimeInterval,
        timing: AetherGooeyTiming,
        update: @escaping (CGFloat) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        cancel()
        self.duration = max(0.001, duration)
        self.timing = timing
        self.update = update
        self.completion = completion
        self.didComplete = false
        self.frameCount = 0
        self.startTime = CACurrentMediaTime()
        update(0.0)

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 80.0,
                maximum: 120.0,
                preferred: 120.0
            )
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        guard displayLink != nil || completion != nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        finish(false)
    }

    @objc private func step(_ link: CADisplayLink) {
        frameCount += 1
        let elapsed = link.targetTimestamp - startTime
        let linear = CGFloat(min(1.0, max(0.0, elapsed / duration)))
        let eased = easedProgress(linear)
        update?(eased)
        if linear >= 1.0 {
            displayLink?.invalidate()
            displayLink = nil
            update?(1.0)
            finish(true)
        }
    }

    private func finish(_ finished: Bool) {
        guard !didComplete else { return }
        didComplete = true
        let completion = self.completion
        self.update = nil
        self.completion = nil
        completion?(finished)
    }

    private func easedProgress(_ value: CGFloat) -> CGFloat {
        switch timing {
        case .easeInOut:
            return AetherGooeyMath.smootherstep(0.0, 1.0, value)
        case let .cubicBezier(x1, y1, x2, y2):
            return AetherGooeyMath.cubicBezierProgress(
                value,
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2
            )
        case let .spring(damping, response):
            return AetherGooeyMath.softSpring01(
                value,
                response: max(0.01, response),
                dampingRatio: max(0.01, damping),
                overshootLimit: 1.018
            )
        }
    }
}

// MARK: - Math

enum AetherGooeyMath {
    static func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    static func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    static func lerpPoint(_ from: CGPoint, _ to: CGPoint, _ progress: CGFloat) -> CGPoint {
        CGPoint(
            x: lerp(from.x, to.x, progress),
            y: lerp(from.y, to.y, progress)
        )
    }

    static func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        let t = clamp(progress, 0.0, 1.0)
        return CGRect(
            x: lerp(from.minX, to.minX, t),
            y: lerp(from.minY, to.minY, t),
            width: lerp(from.width, to.width, t),
            height: lerp(from.height, to.height, t)
        )
    }

    static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = clamp(t, 0.0, 1.0)
        return x * x * (3.0 - 2.0 * x)
    }

    static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge1 != edge0 else { return value >= edge1 ? 1.0 : 0.0 }
        let x = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0)
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }

    static func cubicBezierProgress(
        _ x: CGFloat,
        x1: CGFloat,
        y1: CGFloat,
        x2: CGFloat,
        y2: CGFloat
    ) -> CGFloat {
        let targetX = clamp(x, 0.0, 1.0)
        guard targetX > 0.0, targetX < 1.0 else {
            return targetX
        }

        var t = targetX
        for _ in 0..<6 {
            let currentX = cubicBezierCoordinate(t, p1: x1, p2: x2)
            let derivative = cubicBezierDerivative(t, p1: x1, p2: x2)
            guard abs(derivative) > 0.0001 else { break }
            let next = t - (currentX - targetX) / derivative
            if next < 0.0 || next > 1.0 {
                break
            }
            t = next
        }

        if cubicBezierCoordinate(t, p1: x1, p2: x2).isNaN {
            t = targetX
        }

        var lower: CGFloat = 0.0
        var upper: CGFloat = 1.0
        for _ in 0..<8 where abs(cubicBezierCoordinate(t, p1: x1, p2: x2) - targetX) > 0.0005 {
            if cubicBezierCoordinate(t, p1: x1, p2: x2) < targetX {
                lower = t
            } else {
                upper = t
            }
            t = (lower + upper) * 0.5
        }

        return clamp(cubicBezierCoordinate(t, p1: y1, p2: y2), 0.0, 1.0)
    }

    private static func cubicBezierCoordinate(_ t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1.0 - t
        return 3.0 * oneMinusT * oneMinusT * t * p1
            + 3.0 * oneMinusT * t * t * p2
            + t * t * t
    }

    private static func cubicBezierDerivative(_ t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1.0 - t
        return 3.0 * oneMinusT * oneMinusT * p1
            + 6.0 * oneMinusT * t * (p2 - p1)
            + 3.0 * t * t * (1.0 - p2)
    }

    static func easeOutBack(_ t: CGFloat, overshoot: CGFloat) -> CGFloat {
        let x = clamp(t, 0.0, 1.0) - 1.0
        let c1 = 1.70158 + overshoot * 10.0
        let c3 = c1 + 1.0
        return 1.0 + c3 * x * x * x + c1 * x * x
    }

    static func dampedSpring01(
        _ t: CGFloat,
        response: CGFloat,
        dampingRatio: CGFloat,
        overshootLimit: CGFloat
    ) -> CGFloat {
        let x = clamp(t, 0.0, 1.0)
        guard x > 0.0, x < 1.0 else { return x }
        let omega = 2.0 * .pi / max(0.01, response)
        let damping = max(0.01, dampingRatio)
        let envelope = exp(-damping * 5.8 * x)
        let value = 1.0 - envelope * cos(omega * Double(x) * 0.34)
        return clamp(CGFloat(value), 0.0, overshootLimit)
    }

    static func softSpring01(
        _ t: CGFloat,
        response: CGFloat,
        dampingRatio: CGFloat,
        overshootLimit: CGFloat
    ) -> CGFloat {
        let x = clamp(t, 0.0, 1.0)
        guard x > 0.0, x < 1.0 else { return x }

        let base = 1.0 - pow(1.0 - x, 2.35)
        let settleStart = smootherstep(0.34, 1.0, x)
        let dampingEnergy = clamp(1.0 - dampingRatio, 0.0, 0.5)
        let responseEnergy = clamp(0.42 / max(0.01, response), 0.72, 1.35)
        let overshoot = sin(.pi * settleStart)
            * (1.0 - x)
            * dampingEnergy
            * responseEnergy
            * 0.035
        return clamp(base + overshoot, 0.0, overshootLimit)
    }

    static func normalizedVector(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.001 else {
            return CGPoint(x: 0.0, y: 1.0)
        }
        return CGPoint(x: dx / length, y: dy / length)
    }
}

private enum AetherGooeyInstrumentation {
    static let log = OSLog(subsystem: "AetherUI", category: "GooeyContextMenuTransition")
}
