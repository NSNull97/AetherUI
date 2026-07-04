# Aether Gooey Context Menu Transition

`AetherGooeyContextMenuTransition` is a visual transition primitive for Aether context menus. It is not a menu controller.

The transition owns:

- temporary source snapshot;
- non-interactive overlay cleanup;
- gooey connector path generation;
- temporary shell frame/corner choreography;
- optical highlight choreography that never distorts readable menu content;
- Reduce Motion / Reduce Transparency visual fallbacks.

The existing context menu still owns:

- menu items and actions;
- submenu behavior;
- row highlight and selection;
- dismissal policy;
- tap-outside handling;
- final hit testing;
- accessibility of real menu rows.

Open flow:

1. `ContextMenuController` creates the real `MenuGlassSurfaceView` pre-staged invisible.
2. The source is leased through `SourcePresentationLease`.
3. `AetherGooeyContextMenuTransition` adds a non-interactive overlay.
4. The temporary shell grows from the source frame toward the final menu frame.
5. Source snapshot, metaball connector and morph surface bridge the handoff.
6. Menu rows reveal only after the surface is near final size.
7. The overlay is removed and the menu becomes interactive after completion.

Close flow:

1. Menu rows fade out before any visible squeeze.
2. The temporary shell collapses back toward the source proxy.
3. The source proxy fades in during the tail of the collapse.
4. Shared controller cleanup releases the source lease and removes the host.

The `.gooey` mode is intentionally separate from `.fluidMorph`, so callers can compare both transitions.
