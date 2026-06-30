# Aether App Runtime Review Prompt

Проведи строгий review реализации декларативного AetherApp runtime.

Проверь:

1. Delegate coverage:
- все UIApplicationDelegate methods из текущего SDK попали в audit;
- все UISceneDelegate methods попали в audit;
- все UIWindowSceneDelegate methods попали в audit;
- для каждого метода есть safe default и selector gate policy.

2. Selector-gating:
- optional selectors не exposed без handler-а;
- runtime-required selectors exposed;
- deprecated/legacy selectors disabled by default;
- `responds(to:)` протестирован;
- presence optional methods не ломает UIKit defaults.

3. Builder:
- `Application: AetherApp { var current: some ApplicationBuilder { ... } }` работает;
- conditional/array builder работает;
- plugins install handlers correctly;
- duplicate handlers compose predictably.

4. AppDelegate proxy:
- launch order корректный;
- return values composed correctly;
- URL handling firstHandled;
- notifications/background completions exactly once;
- no blocking work on main thread;
- no double forwarding to legacy delegate.

5. SceneDelegate proxy:
- scene connect creates correct scene instance;
- window created once;
- render called at correct moments;
- scene phase mapping correct;
- multi-scene isolation correct;
- scene disconnect releases memory.

6. Window integration:
- AetherWindow runtime используется, а не дублируется;
- UIWindow не пересоздаётся на render update;
- root state не сбрасывается при phase/trait changes.

7. Migration:
- existing AppDelegate bridge работает;
- existing SceneDelegate bridge strategy documented;
- old and new handlers order deterministic;
- no double URL/push/background handling.

8. Diagnostics:
- runtime dump показывает scenes/handlers/selectors;
- audit docs актуальны;
- signpost policy documented.

9. Safety:
- no private UIKit API;
- no SwiftUI hard dependency;
- no ASDK/Telegram dependency;
- no retain cycles;
- completion handlers one-shot.

Составь список issues с приоритетами P0/P1/P2. P0 и P1 исправь сразу.
