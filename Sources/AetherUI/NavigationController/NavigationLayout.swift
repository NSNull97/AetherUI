import UIKit

enum RootNavigationLayout {
    case split([AetherViewController], [AetherViewController])
    case flat([AetherViewController])
}

struct NavigationLayout {
    var root: RootNavigationLayout
}

func makeNavigationLayout(mode: NavigationControllerMode, layout: ContainerViewLayout, controllers: [AetherViewController]) -> NavigationLayout {
    let rootLayout: RootNavigationLayout
    switch mode {
    case .single:
        rootLayout = .flat(controllers)
    case .automaticMasterDetail:
        switch layout.metrics.widthClass {
        case .compact:
            rootLayout = .flat(controllers)
        case .regular:
            let masterControllers = controllers.filter {
                if case .master = $0.navigationPresentation { return true }
                return false
            }
            let detailControllers = controllers.filter {
                if case .master = $0.navigationPresentation { return false }
                return true
            }
            rootLayout = .split(masterControllers, detailControllers)
        }
    }

    return NavigationLayout(root: rootLayout)
}
