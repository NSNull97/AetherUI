# AetherAppearance Availability Audit

Phase 17 audit for the new appearance runtime.

## Public Runtime Contract

- `AetherAppearanceStyle` is a fixed public enum with exactly `.iOS26` and `.iOS27`.
- `AetherAppearance` is pure data and does not resolve style from OS version, process state, feature flags, or user defaults.
- `AppearanceStyle(.iOS26/.iOS27)` writes directly into `AetherApplicationRuntimeConfiguration.environment`.
- Runtime updates use `AetherApplicationRuntime.updateAppearanceStyle(_:)` / `updateAppearance(_:)` and update already visible bar controllers in place.

## Availability Boundary

| Area | Existing availability/private risk | New runtime action |
| --- | --- | --- |
| `SystemGlassEffect` | Uses public `UIGlassEffect` behind `#available(iOS 26.0, *)` and material blur fallback otherwise. | Reuses the helper; adds `.strong` mapping without adding new private lookups. |
| `GlassBackgroundView` / glass controls | Existing glass infrastructure already gates native glass availability. | Appearance model passes `SystemGlassEffectStyle`; it does not expose runtime availability decisions. |
| `EdgeEffectView` | Existing implementation can use private CoreAnimation filters for variable blur. | Appearance runtime only supplies data (`AetherEdgeEffectAppearance`) and does not introduce new private API. |
| `VisualEffectView` legacy blur helpers | Existing renderer internals contain reflection/KVC paths. | Not part of the new public appearance API; no new appearance resolver depends on those symbols. |
| iOS 26/27 styles | iOS 27 is a design preset, not an SDK availability branch. | `.iOS27` can be selected on any supported deployment target and falls back through existing renderer capabilities. |

## Compliance Notes

- No `.automatic`, `.custom`, style id, OS-version resolver, or fallback chain was added to `AetherAppearanceStyle`.
- `.clear` remains on existing `SystemGlassEffectStyle` because it was already public API used by glass configuration; it is not an app appearance style.
- The new runtime does not recreate windows or root controllers when appearance changes. It traverses connected controller hierarchies and updates visible nav/tab/standalone bar renderers.
