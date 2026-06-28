import UIKit

public final class AetherKeyboardManager {
    public private(set) weak var window: UIWindow?
    public private(set) var state = AetherKeyboardState()
    public var stateChanged: ((AetherKeyboardState, ContainedViewLayoutTransition) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var surfaces: [AetherKeyboardSurface] = []
    private var interactiveInputOffset: CGFloat = 0.0
    private weak var previousFirstResponderSurfaceHost: UIView?

    public init(window: UIWindow? = nil) {
        self.window = window
    }

    deinit {
        stop()
    }

    public func attach(to window: UIWindow) {
        self.window = window
    }

    public func start() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardDidShowNotification,
            UIResponder.keyboardDidHideNotification,
            UIResponder.keyboardDidChangeFrameNotification
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleKeyboardNotification(notification)
            }
        }
    }

    public func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    public func setSurfaces(_ surfaces: [AetherKeyboardSurface]) {
        let previousSurfaces = self.surfaces
        self.surfaces = surfaces
        updateSurfaces(previousSurfaces)
    }

    public func updateInteractiveInputOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        interactiveInputOffset = offset
        state.isInteractive = !offset.isZero
        state.source = .manual
        stateChanged?(state, transition)
        AetherLegacyKeyboardRuntime.updateInteractiveKeyboardOffset(
            offset,
            transition: transition,
            completion: completion
        )
    }

    public func cancelInteractiveKeyboardGestures() {
        guard !interactiveInputOffset.isZero else { return }
        updateInteractiveInputOffset(0.0, transition: .animated(duration: 0.25, curve: .spring))
    }

    public func dismissEditingWithoutAnimation(in view: UIView) {
        guard view.findFirstResponder() != nil else { return }
        UIView.performWithoutAnimation {
            view.endEditing(true)
            Self.removeAnimationsRecursively(from: view)
            AetherLegacyKeyboardRuntime.removeKeyboardAnimations()
        }
    }

    public func currentFirstResponder(in rootView: UIView?) -> UIView? {
        rootView?.findFirstResponder()
    }

    public static func state(
        from notification: Notification,
        in window: UIWindow
    ) -> (AetherKeyboardState, ContainedViewLayoutTransition) {
        let userInfo = notification.userInfo ?? [:]
        let screenFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let frameInWindow = window.convert(screenFrame, from: nil)
        let intersection = window.bounds.intersection(frameInWindow)
        let height = max(0.0, intersection.height)
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0
        let rawCurve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? UIView.AnimationCurve.easeInOut.rawValue
        let curve = UIView.AnimationCurve(rawValue: rawCurve) ?? .easeInOut
        let isHiding = notification.name == UIResponder.keyboardWillHideNotification || notification.name == UIResponder.keyboardDidHideNotification
        let isVisible = !isHiding && height > 0.0

        let state = AetherKeyboardState(
            isVisible: isVisible,
            frameInWindow: frameInWindow,
            height: isVisible ? height : 0.0,
            animationDuration: duration,
            animationCurve: curve,
            isInteractive: false,
            source: .notification
        )

        let transitionCurve: ContainedViewLayoutTransitionCurve = curve == .easeInOut ? .easeInOut : .spring
        let transition: ContainedViewLayoutTransition = duration > .ulpOfOne
            ? .animated(duration: duration, curve: transitionCurve)
            : .immediate
        return (state, transition)
    }

    private func handleKeyboardNotification(_ notification: Notification) {
        guard let window else { return }
        let parsed = Self.state(from: notification, in: window)
        state = parsed.0
        stateChanged?(parsed.0, parsed.1)
        updateSurfaces(surfaces)
    }

    private func updateSurfaces(_ previousSurfaces: [AetherKeyboardSurface]) {
        _ = previousSurfaces

        guard !surfaces.isEmpty else {
            previousFirstResponderSurfaceHost = nil
            AetherLegacyKeyboardRuntime.updateKeyboardLeftEdge(0.0, transition: .immediate)
            return
        }

        var firstResponderSurfaceHost: UIView?
        var handlingOptions: AetherKeyboardAutomaticHandlingOptions = []

        for surface in surfaces {
            guard let hostView = surface.hostView,
                  let firstResponder = hostView.findFirstResponder() else {
                continue
            }
            firstResponderSurfaceHost = hostView
            handlingOptions = surface.automaticHandlingOptions
            handlingOptions.formUnion(hostView.aetherKeyboardAutomaticHandlingOptions)
            handlingOptions.formUnion(firstResponder.aetherKeyboardAutomaticHandlingOptions)
            break
        }

        if let firstResponderSurfaceHost {
            let containerOrigin = firstResponderSurfaceHost.convert(CGPoint.zero, to: nil)
            var filteredTranslation = containerOrigin.x
            if handlingOptions.contains(.disableForward) {
                filteredTranslation = max(0.0, filteredTranslation)
            }
            if handlingOptions.contains(.disableBackward) {
                filteredTranslation = min(0.0, filteredTranslation)
            }
            AetherLegacyKeyboardRuntime.updateKeyboardLeftEdge(filteredTranslation, transition: .immediate)
        } else {
            AetherLegacyKeyboardRuntime.updateKeyboardLeftEdge(0.0, transition: .immediate)
            if let previousFirstResponderSurfaceHost, previousFirstResponderSurfaceHost.window == nil {
                AetherLegacyKeyboardRuntime.removeKeyboardAnimations()
            }
        }

        previousFirstResponderSurfaceHost = firstResponderSurfaceHost
    }

    private static func removeAnimationsRecursively(from view: UIView) {
        view.layer.removeAllAnimations()
        for subview in view.subviews {
            removeAnimationsRecursively(from: subview)
        }
    }
}

public final class AetherKeyboardViewManager {
    private weak var manager: AetherKeyboardManager?

    public init(manager: AetherKeyboardManager) {
        self.manager = manager
    }

    public func dismissEditingWithoutAnimation(view: UIView) {
        manager?.dismissEditingWithoutAnimation(in: view)
    }

    public func update(leftEdge: CGFloat, transition: ContainedViewLayoutTransition) {
        AetherLegacyKeyboardRuntime.updateKeyboardLeftEdge(leftEdge, transition: transition)
    }
}

public enum AetherKeyboardAutocorrection {
    public static func apply(to textView: UITextView) {
        let originalRange = textView.selectedRange
        var fakeRange = originalRange
        if fakeRange.location > 0 {
            fakeRange.location -= 1
        }

        textView.unmarkText()

        let textLength = textView.attributedText?.length ?? textView.textStorage.length
        if NSMaxRange(fakeRange) <= textLength {
            textView.selectedRange = fakeRange
        }
        if NSMaxRange(originalRange) <= textLength {
            textView.selectedRange = originalRange
        }
    }
}
