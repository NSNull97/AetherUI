Проведи строгий review портирования Aether Window runtime.

Проверь:

1. Source parity:
   - изучены ли NativeWindowHostView.swift, ChildWindowHostView.swift, PresentationContext.swift, KeyboardManager.swift, Keyboard.swift, Portal/GlobalOverlay файлы;
   - есть ли AetherWindowPortAudit.md;
   - описаны ли все missing behaviors.

2. Private API:
   - private keyboard compatibility ограничена internal runtime и не выходит в public API;
   - нет ли private selector/class strings вне явно задокументированного keyboard bridge;
   - нет ли configuration-based переключателей поведения;
   - есть public fallback;
   - есть binary/source scan test.

3. Window:
   - UIWindow subclass корректен;
   - root VC корректен;
   - hitTest bridge корректен;
   - layout updates не reentrant;
   - accessibilityElements bridge корректен.

4. Presentation:
   - levels sorted correctly;
   - block interaction tokens корректны;
   - lifecycle не дублируется;
   - status bar winner корректен;
   - opaque overlay скрывает lower accessibility.

5. Keyboard:
   - keyboard handling через единый public API работает;
   - interactive dismissal не прыгает;
   - first responder tracking корректен;
   - dismissEditingWithoutAnimation работает;
   - private keyboardWindow/keyboardView не доступны внешним приложениям;
   - chat input panel demo стабилен.

6. Orientation/system UI:
   - iOS 16+ scene geometry update path есть;
   - старые private hacks не используются;
   - home indicator/screen edge deferral работают;
   - rotation during overlay/keyboard не ломается.

7. Portal/global overlay:
   - portal fallback работает;
   - source lifecycle корректен;
   - no duplicate accessibility;
   - global overlay z-order/hit testing корректны.

8. Memory:
   - no retain cycles;
   - display links invalidated;
   - observers removed;
   - controllers deinit after dismiss.

Составь список issues с priority P0/P1/P2.
P0 и P1 исправь сразу.
