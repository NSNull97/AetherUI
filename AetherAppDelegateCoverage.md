# Aether App Delegate Coverage

The authoritative coverage table is in `AetherAppRuntimeAudit.md`.

Implemented first-slice paths:

- Launch: will/did finish.
- App active/background/memory/time/termination callbacks.
- Scene configuration and discarded session cleanup.
- URL routing through app and scene delegates.
- User activity routing through app and scene delegates.
- Remote notification registration and receive callbacks.
- Background fetch and background URL session callbacks with one-shot completions.
- App and window-scene quick action callbacks with safe `false` default.
- Secure app state restoration handlers and scene restoration hooks.
- Scene connect/disconnect/active/background lifecycle.
- Window scene coordinate/orientation/trait update invalidation.

Audited but not implemented in the first slice:

- Health authorization delegate callback.
- Intents handler callbacks.
- CloudKit share acceptance callbacks.
- iOS 26 `windowScene(_:didUpdateEffectiveGeometry:)`.
- iOS 26 preferred windowing control style.
- Deprecated pre-iOS 9 URL callbacks and deprecated insecure state restoration callbacks.

All optional selectors remain hidden unless enabled by `AetherDelegateMethodRegistry`.
