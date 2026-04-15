import UIKit

/// Root navigation layout mode.
enum RootNavigationLayout {
    case split([ViewController], [ViewController])
    case flat([ViewController])
}

/// Modal container layout configuration.
struct ModalContainerLayout {
    var controllers: [ViewController]
    var isFlat: Bool
    var flatReceivesModalTransition: Bool
    var isStandalone: Bool
}

/// Computed navigation layout result.
struct NavigationLayout {
    var root: RootNavigationLayout
    var modal: [ModalContainerLayout]
}

/// Computes the navigation layout from a flat list of view controllers,
/// separating them into root (flat or split) and modal stacks.
func makeNavigationLayout(mode: NavigationControllerMode, layout: ContainerViewLayout, controllers: [ViewController]) -> NavigationLayout {
    var rootControllers: [ViewController] = []
    var modalStack: [ModalContainerLayout] = []

    for controller in controllers {
        let requiresModal: Bool
        var beginsModal = false
        var isFlat = false
        let flatReceivesModalTransition = controller.flatReceivesModalTransition
        var isStandalone = false

        switch controller.navigationPresentation {
        case .default:
            requiresModal = false
        case .master:
            requiresModal = false
        case .modal:
            requiresModal = true
            beginsModal = true
        case .flatModal:
            requiresModal = true
            beginsModal = true
            isFlat = true
        case .standaloneModal:
            requiresModal = true
            beginsModal = true
            isStandalone = true
        case .standaloneFlatModal:
            requiresModal = true
            beginsModal = true
            isStandalone = true
            isFlat = true
        case .modalInLargeLayout:
            switch layout.metrics.widthClass {
            case .compact:
                requiresModal = false
            case .regular:
                requiresModal = true
            }
        case .modalInCompactLayout:
            switch layout.metrics.widthClass {
            case .compact:
                requiresModal = true
            case .regular:
                requiresModal = true
                beginsModal = true
                isFlat = true
            }
        }

        if requiresModal {
            controller._presentedInModal = true
            if beginsModal || modalStack.isEmpty || modalStack[modalStack.count - 1].isStandalone {
                modalStack.append(ModalContainerLayout(controllers: [controller], isFlat: isFlat, flatReceivesModalTransition: flatReceivesModalTransition, isStandalone: isStandalone))
            } else {
                modalStack[modalStack.count - 1].controllers.append(controller)
            }
        } else if !modalStack.isEmpty {
            if !modalStack[modalStack.count - 1].isFlat {
                controller._presentedInModal = true
            }
            if modalStack[modalStack.count - 1].isStandalone {
                modalStack.append(ModalContainerLayout(controllers: [controller], isFlat: isFlat, flatReceivesModalTransition: flatReceivesModalTransition, isStandalone: isStandalone))
            } else {
                modalStack[modalStack.count - 1].controllers.append(controller)
            }
        } else {
            controller._presentedInModal = false
            rootControllers.append(controller)
        }
    }

    let rootLayout: RootNavigationLayout
    switch mode {
    case .single:
        rootLayout = .flat(rootControllers)
    case .automaticMasterDetail:
        switch layout.metrics.widthClass {
        case .compact:
            rootLayout = .flat(rootControllers)
        case .regular:
            let masterControllers = rootControllers.filter {
                if case .master = $0.navigationPresentation { return true }
                return false
            }
            let detailControllers = rootControllers.filter {
                if case .master = $0.navigationPresentation { return false }
                return true
            }
            rootLayout = .split(masterControllers, detailControllers)
        }
    }

    return NavigationLayout(root: rootLayout, modal: modalStack)
}
