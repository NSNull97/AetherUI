# Gooey Context Menu Guide

Enable the transition with the new presentation style:

```swift
let menu = ContextMenuController(
    source: ContextMenuController.Source(view: button, cornerRadius: button.bounds.height / 2),
    items: items,
    presentationStyle: .gooey()
)
menu.present()
```

Customize timing and glass density by passing a configuration:

```swift
var configuration = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .iOS27)
configuration.connectorMaximumThickness = 34.0
configuration.debugShowsControlPoints = true

ContextMenuController.present(
    source: button,
    cornerRadius: button.bounds.height / 2,
    items: items,
    presentationStyle: .gooey(configuration: configuration)
)
```

Defaults are appearance-aware:

- `.iOS26`: regular glass, softer stroke, more elastic connector.
- `.iOS27`: stronger glass, stronger stroke, denser connector.

The transition captures geometry from presentation layers when possible and converts source/menu frames into the window overlay coordinate space. If the source disappears before close, the transition falls back to an anchor near the menu edge instead of crashing.

Do not route menu actions through `AetherGooeyContextMenuTransition`. Keep actions in `ContextMenuItem` and dismissal in `ContextMenuDismissHandle`.
