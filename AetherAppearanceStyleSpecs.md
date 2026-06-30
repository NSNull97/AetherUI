# AetherAppearance Style Specs

`AetherAppearanceStyle` has two public cases:

```swift
public enum AetherAppearanceStyle {
    case iOS26
    case iOS27
}
```

No `.automatic`, `.custom`, style id, or OS resolver exists.

## Preset Values

| Field | `.iOS26` | `.iOS27` |
| --- | --- | --- |
| `overallDarkAppearance` | `false` | `false` |
| `emptyAreaColor` | `.systemBackground` | `.systemBackground` |
| `edgeEffectAlpha` | `0.75` | `0.75` |
| `edgeEffectBlurRadiusAtEdge` | `2.0` | `5.0` |
| `edgeEffectBlurRadiusAtFade` | `0.0` | `5.0` |
| `edgeEffectStyle` | `.regular` | `.strong` |
| `separatorColor` | `.separator` | `.separator` |

Use `AetherAppearanceSignature` when tests or caches need equality across `UIColor` fields.
