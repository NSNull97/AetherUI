import UIKit

enum BarButtonVisualStyle {
    case plain
    case glass
    case prominentGlass
    case text
    case custom
}

enum BarButtonPresentationBehavior {
    case persistentPlain
    case glassMorphSource
    case menuSourceProxy
    case replaceInSlot
    case hiddenOnlyWhenCoveredByProxy
}

enum BarButtonSourceOwnershipState {
    case idle
    case pressed
    case leasedToPresentation
    case representedByProxy
    case suppressedOriginal
    case restoringOriginal
}

struct BarButtonID: Hashable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String {
        rawValue
    }
}

enum PressDragState {
    case pressed
    case dragging(translation: CGPoint)
    case released
}

enum SourceReleaseOutcome {
    case completed
    case cancelled
    case originalRemoved
}

final class OriginalVisibilityToken {
    private weak var view: UIView?
    private let originalAlpha: CGFloat
    private let originalIsUserInteractionEnabled: Bool
    private var didSuppress = false
    private var didDisableInteraction = false

    init(view: UIView) {
        self.view = view
        self.originalAlpha = view.alpha
        self.originalIsUserInteractionEnabled = view.isUserInteractionEnabled
    }

    var canRestore: Bool {
        guard let view else { return false }
        return view.superview != nil && view.window != nil
    }

    func disableInteraction() {
        guard let view else { return }
        didDisableInteraction = true
        view.isUserInteractionEnabled = false
    }

    func suppressOriginalIfCovered() {
        guard let view else { return }
        didSuppress = true
        view.alpha = 0.0
        view.isUserInteractionEnabled = false
    }

    func restoreVisualState(interactive: Bool) {
        guard canRestore, let view else { return }
        if didSuppress {
            view.alpha = originalAlpha
        }
        if didDisableInteraction || didSuppress {
            view.isUserInteractionEnabled = interactive ? originalIsUserInteractionEnabled : false
        }
    }

    func restoreInteractionOnly() {
        guard canRestore, let view else { return }
        if didDisableInteraction || didSuppress {
            view.isUserInteractionEnabled = originalIsUserInteractionEnabled
        }
    }
}

final class PresentationSourceLease {
    let sourceID: BarButtonID
    weak var originalView: UIView?
    let proxyView: UIView
    let originalVisibilityToken: OriginalVisibilityToken

    private weak var overlayView: UIView?
    private let visualStyle: BarButtonVisualStyle
    private let behavior: BarButtonPresentationBehavior
    private var state: BarButtonSourceOwnershipState = .idle
    private var isFinished = false
    private var didNotifyFinish = false
    var onDidFinish: ((BarButtonID) -> Void)?

    init?(
        sourceID: BarButtonID,
        originalView: UIView,
        overlayView: UIView,
        visualStyle: BarButtonVisualStyle,
        behavior: BarButtonPresentationBehavior
    ) {
        guard originalView.bounds.width > 0.0, originalView.bounds.height > 0.0 else {
            return nil
        }
        self.sourceID = sourceID
        self.originalView = originalView
        self.overlayView = overlayView
        self.visualStyle = visualStyle
        self.behavior = behavior
        self.originalVisibilityToken = OriginalVisibilityToken(view: originalView)
        self.proxyView = PresentationSourceLease.makeProxyView(from: originalView)
        self.proxyView.isUserInteractionEnabled = false
    }

    func acquire() {
        guard !isFinished, let originalView, let overlayView else { return }

        state = .leasedToPresentation
        let initialFrame = originalView.convert(originalView.bounds, to: overlayView)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        proxyView.frame = initialFrame
        proxyView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        proxyView.center = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
        proxyView.alpha = 1.0
        proxyView.transform = originalView.transform

        if proxyView.superview !== overlayView {
            overlayView.addSubview(proxyView)
        }
        overlayView.bringSubviewToFront(proxyView)

        originalVisibilityToken.disableInteraction()
        state = .representedByProxy

        if shouldSuppressOriginal {
            originalVisibilityToken.suppressOriginalIfCovered()
            state = .suppressedOriginal
        }
        CATransaction.commit()

        assert(proxyView.superview != nil, "A bar-button source proxy must be installed before suppressing its original.")
        assert(originalView.isUserInteractionEnabled == false, "A proxied bar-button source must not stay interactive.")
        assert(!shouldSuppressOriginal || originalView.alpha == 0.0 || originalView.isHidden, "A suppressed bar-button source must not stay visible while proxied.")
    }

    func updateForPressOrDrag(_ state: PressDragState) {
        guard !isFinished else { return }
        switch state {
        case .pressed:
            self.state = .pressed
            UIView.animate(
                withDuration: 0.085,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.proxyView.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
                },
                completion: nil
            )
        case let .dragging(translation):
            let limited = CGPoint(
                x: max(-8.0, min(8.0, translation.x)),
                y: max(-8.0, min(8.0, translation.y))
            )
            proxyView.transform = CGAffineTransform(translationX: limited.x, y: limited.y).scaledBy(x: 0.985, y: 0.985)
        case .released:
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.proxyView.transform = .identity
                },
                completion: nil
            )
        }
    }

    func release(outcome: SourceReleaseOutcome) {
        guard !isFinished else { return }
        isFinished = true
        state = .restoringOriginal

        let shouldRestoreOriginal = outcome != .originalRemoved && originalVisibilityToken.canRestore
        let restoreOriginal = { [weak self] (interactive: Bool) in
            guard let self else { return }
            if shouldRestoreOriginal {
                self.originalVisibilityToken.restoreVisualState(interactive: interactive)
            }
        }

        if shouldRestoreOriginal, let originalView {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            originalView.layer.removeAllAnimations()
            restoreOriginal(false)
            CATransaction.commit()
        }

        UIView.animate(
            withDuration: outcome == .cancelled ? 0.12 : 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.proxyView.alpha = 0.0
                self.proxyView.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            },
            completion: { [weak self] _ in
                guard let self else { return }
                guard !self.didNotifyFinish else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.proxyView.removeFromSuperview()
                self.proxyView.transform = .identity
                restoreOriginal(true)
                CATransaction.commit()
                self.state = .idle
                self.notifyFinishIfNeeded()
            }
        )
    }

    func cancel() {
        isFinished = true
        proxyView.layer.removeAllAnimations()
        proxyView.removeFromSuperview()
        proxyView.transform = .identity
        originalVisibilityToken.restoreVisualState(interactive: true)
        state = .idle
        notifyFinishIfNeeded()
    }

    private var shouldSuppressOriginal: Bool {
        switch behavior {
        case .persistentPlain:
            return false
        case .glassMorphSource, .menuSourceProxy, .hiddenOnlyWhenCoveredByProxy:
            return proxyView.superview != nil
        case .replaceInSlot:
            return visualStyle == .glass || visualStyle == .prominentGlass
        }
    }

    private static func makeProxyView(from sourceView: UIView) -> UIView {
        if let snapshot = sourceView.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = sourceView.bounds
            return snapshot
        }

        let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
        let image = renderer.image { _ in
            sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.bounds = sourceView.bounds
        return imageView
    }

    private func notifyFinishIfNeeded() {
        guard !didNotifyFinish else { return }
        didNotifyFinish = true
        onDidFinish?(sourceID)
    }
}

final class SourceProxyCoordinator {
    private var activeLeases: [BarButtonID: PresentationSourceLease] = [:]

    func acquire(
        sourceID: BarButtonID,
        originalView: UIView,
        overlayView: UIView,
        visualStyle: BarButtonVisualStyle,
        behavior: BarButtonPresentationBehavior
    ) -> PresentationSourceLease? {
        if let existing = activeLeases[sourceID] {
            existing.cancel()
        }
        guard let lease = PresentationSourceLease(
            sourceID: sourceID,
            originalView: originalView,
            overlayView: overlayView,
            visualStyle: visualStyle,
            behavior: behavior
        ) else {
            return nil
        }
        activeLeases[sourceID] = lease
        lease.onDidFinish = { [weak self, weak lease] sourceID in
            guard let self, let lease, self.activeLeases[sourceID] === lease else {
                return
            }
            self.activeLeases[sourceID] = nil
        }
        lease.acquire()
        assert(originalView.isUserInteractionEnabled == false, "Original bar-button source must be non-interactive while leased.")
        return lease
    }

    func release(sourceID: BarButtonID, outcome: SourceReleaseOutcome) {
        activeLeases[sourceID]?.release(outcome: outcome)
    }

    func cancel(sourceID: BarButtonID) {
        activeLeases[sourceID]?.cancel()
    }

    func cancelAll() {
        let leases = Array(activeLeases.values)
        activeLeases.removeAll()
        leases.forEach { $0.cancel() }
    }
}
