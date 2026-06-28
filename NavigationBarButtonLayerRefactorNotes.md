# Navigation Bar Button Layer Refactor Notes

## Current hierarchy

`NavigationBarImpl` is the concrete UIKit navigation bar. Before this refactor
its relevant hierarchy is:

```text
  NavigationBarImpl
    NavigationBackgroundView
    stripeView
    clippingView
      buttonsContainerView
        backArrowView
        backButtonView
        titleLabel / subtitleLabel / custom titleView
      leftButtonContainer
        leftButtonGlassContainer
        UIBarButtonItem custom views / generated UIButtons / GlassControlGroup
      rightButtonContainer
        rightButtonGlassContainer
        UIBarButtonItem custom views / generated UIButtons / GlassControlGroup
      badgeView
    NavigationBarContentView accessory/search content
```

After this refactor `buttonsContainerView` remains the title/content-row layout
owner, but top-level button chrome is hosted by a separate sibling view outside
the navigation bar whenever a navigation-bar root host is available:

```text
NavigationController.view / external root host
  NavigationBarImpl
    NavigationBackgroundView
    stripeView
    clippingView
      buttonsContainerView
        titleLabel / subtitleLabel
      NavigationBarContentView accessory/search content
  AetherNavigationBarButtonLayer
    backArrowView
    backButtonView
    leftButtonContainer
      existing item-created button views/groups
    rightButtonContainer
      existing item-created button views/groups
    badgeView
    navigationBarItem.titleView, when a custom title view exists
```

`AetherNavigationBarButtonLayer` mirrors the converted frame of the title/button
row in the external host coordinate space, so existing button layout math and
`ButtonChromeLayout` frame semantics stay in the same local row coordinate space
as before. Standalone `NavigationBarImpl` instances that do not receive an
external `buttonLayerHostView` fall back to internal hosting for compatibility,
but `NavigationController` installs the layer into its root `view`.

## Button ownership and source of truth

`NavigationBarItem` remains the semantic source of truth. It owns the wrapped
`UINavigationItem` fields:

- `leftBarButtonItems` / `rightBarButtonItems`;
- `leftBarButtonItem` / `rightBarButtonItem`;
- `title`, `subtitle`, `titleView`;
- search and top-bar accessory configuration.

`NavigationBarImpl.layoutBarButtonItems(...)` still interprets the current
`NavigationBarItem` and `UIBarButtonItem`s. The new layer does not inspect the
item, decide which buttons exist, build items, or route actions.

## Where buttons are created

Button view creation remains in `NavigationBarImpl.layoutBarButtonItems(...)`.

- Legacy style custom buttons reuse `UIBarButtonItem.customView` directly.
- Legacy style non-custom items create `UIButton(type: .system)` and wire the
  original `target/action` to `.touchUpInside`.
- Glass style builds or reuses `GlassControlGroup` instances. Custom views are
  passed through as `.customView(customView)` or laid out directly when all
  items are custom views and no automatic back button is needed.
- Automatic glass back button is still represented as a `GlassControlGroup.Item`
  whose action calls `backPressed`.
- A custom `navigationBarItem.titleView` is not recreated; the existing view is
  reparented into the button layer. Plain `title` / `subtitle` labels remain in
  `buttonsContainerView`.

## Where handlers and state are assigned

Handlers remain where they were:

- `UIBarButtonItem.target/action` is wired in `layoutBarButtonItems(...)`;
- glass group item closures are created in `layoutBarButtonItems(...)`;
- context menu touch-down actions are attached by
  `wireBarButtonMenuTrigger(...)`;
- `NavigationBackButtonView.action` still calls `backButtonPressed()`;
- `GlassControlGroup` owns its internal highlight/tap tracking for group cells.

The button layer stores no action closures and never calls navigation actions.

## Where visual properties are applied

Before the refactor, top-level button chrome frames were applied directly to
`leftButtonContainer`, `rightButtonContainer`, `backArrowView`,
`backButtonView`, and `badgeView` inside `NavigationBarImpl`.

After the refactor, those top-level placements are routed through
`AetherNavigationBarButtonLayer.applyButtonPlacements(...)` when separated
hosting is active. `NavigationBarImpl` computes the same local frames as before,
then converts the button-row host frame into `buttonLayerHostView` coordinate
space. Existing internal layout inside `leftButtonContainer`,
`rightButtonContainer`, and `GlassControlGroup` is intentionally left in place
because those views remain the existing render objects for item-created button
content.

## Animations and morph-related code

The existing animation state machine remains in `NavigationBarImpl` and
`NavigationController`:

- `ContainedViewLayoutTransition` is still the timing/curve carrier;
- `withButtonMorphTransition(...)` still controls button morph layout updates;
- `buttonChromeLayout()` / `setButtonChromeLayout(...)` still expose and apply
  the same left/right chrome frames;
- interactive push/pop button effects still use
  `setButtonChromeAlpha(...)`, `setButtonTransitionEffects(...)`, and
  `setButtonContentTransform(...)`;
- navigation transitions no longer install temporary source/target button bars
  or bar-button source proxy/snapshot leases.

`AetherNavigationBarButtonLayer` only provides stable physical hosting,
hit-testing, accessibility ordering, and frame conversion helpers for hosted
views.

## Do-not-touch areas

The refactor intentionally does not change:

- `NavigationBarItem` public API or notification behavior;
- `UIBarButtonItem` target/action or context menu wiring;
- automatic back/cancel/close navigation routing;
- `GlassControlGroup` item diffing, highlight tracking, or internal button
  state;
- title-transition bars for ordinary title/subtitle content;
- public `NavigationBarView` protocol surface.

## New types

- `AetherNavigationBarButtonLayer`: visual portal for existing button views.
- `AetherNavigationBarButtonPlacement`: stable visual placement for an existing
  view.
- `AetherNavigationBarButtonTransition`: adapter over the existing
  `ContainedViewLayoutTransition`.
- `AetherNavigationBarButtonHostingMode`: internal comparison flag with
  `.legacyInline` and `.separatedLayer`.
- `NavigationBarImpl.buttonLayerHostView`: internal external-host attachment
  point used by `NavigationController` to keep the visual button layer outside
  the navigation bar view.

## Ownership invariant

`NavigationBarItem` owns what buttons mean and what they do.
`NavigationBarImpl` computes how they are laid out and animated.
`AetherNavigationBarButtonLayer` owns only where existing button views live in
the view hierarchy and how already-computed visual placements are applied.
