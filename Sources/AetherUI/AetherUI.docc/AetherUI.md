# ``AetherUI``

UIKit-фреймворк навигации с glass-morphism, морф-переходами и плавающим tab bar для iOS 13+.

## Overview

AetherUI представляет собой переписанную с нуля поверх современного UIKit
реализацию ключевых навигационных компонентов, спроектированных по образцу
Telegram-iOS, но без зависимости от `ASDisplayNode` и legacy-инфраструктуры.
Целевой визуальный стиль — iOS 26 liquid glass: blur-фоны, edge-эффекты на
границе скролл-контента, glass-morph переходы кнопок и плавающие pill-контейнеры.

Основные компоненты фреймворка:

- ``AetherViewController`` — базовый контроллер с собственным nav bar, accessory-зонами
  и единой точкой раскладки для tab bar, floating toolbar и content-unavailable
  overlay.
- ``AetherNavigationController`` — стек экранов с per-screen nav bar,
  glass-morph переходами при push/pop и интерактивным edge-swipe pop'ом.
- ``AetherTabBarController`` — корневой tab bar с плавающим pill-контейнером,
  опциональным search-кружком в стиле Apple Music и `bottomBarAccessory`-полосой
  над pill'ом.
- ``AetherWindow`` — `UIWindow`-подкласс с keyboard tracking, интерактивным
  drag-to-dismiss клавиатуры и status bar dispatcher'ом.
- Семейство **glass-примитивов** (``GlassBackgroundView``, ``GlassControlGroup``,
  ``GlassButton``, ``EdgeEffectView``, ``LiquidLensView``) — компоненты, на
  основе которых построены nav bar, tab bar, modals, context menu и toolbar.
- Готовые sheets и оверлеи: ``AetherModalController``,
  ``AetherActionSheetController``, ``AetherAlertController``,
  ``AetherToastController``, ``AetherTooltipController``,
  ``AetherContextMenuController``.
- Высокопроизводительный ``AetherListView`` — порт `Display.ListView` из
  Telegram-iOS на чистом UIKit (виртуализация, transactions, sticky headers,
  Metal-частицы).

> Important: AetherUI требует iOS 13.0+ и Swift 5.9+. Для liquid-glass-эффектов,
> зависящих от системного `UIGlassEffect`, требуется iOS 26+. На более ранних
> версиях используется legacy-fallback (`UIVisualEffectView` с тонированными
> слоями).

## Архитектура одного экрана

Иерархия контроллеров и view-объектов на типовом экране:

```
AetherNativeWindow / AetherWindow
 └── AetherWindowRootViewController      // status bar / orientation / system UI
      └── AetherTabBarController
           ├── TabBarView                  // floating glass pill + search
           ├── (опц.) TabBarAccessoryView  // полоса над pill'ом (Now Playing и т.п.)
           └── AetherNavigationController (per tab)
                ├── NavigationBarView      // принадлежит топовому ViewController
                ├── ViewController.view    // контент приложения
                └── (опц.) AetherFloatingToolbarView
```

Каждый ``AetherViewController`` владеет **собственным** ``NavigationBarView``. Бар не
является shared-объектом; он перемещается синхронно с контроллером во время
push/pop. Это ключевое архитектурное решение: плавный glass-morph между
экранами достигается за счёт того, что два бара одновременно перекрашиваются
и сдвигаются в рамках единого transition'а, а не за счёт морфинга контента
внутри одного общего бара.

## Quick links

@Links(visualStyle: detailedGrid) {
    - <doc:QuickStart>
    - <doc:ViewController>
    - <doc:NavigationController>
    - <doc:TabBar>
    - <doc:Glass>
}

## Topics

### С чего начать

- <doc:QuickStart>

### Основа

- <doc:ViewController>
- <doc:AetherWindow>

### Навигация

- <doc:NavigationController>
- <doc:NavigationBar>
- <doc:Search>

### Tab Bar

- <doc:TabBar>

### Glass-примитивы

- <doc:Glass>
- <doc:EdgeEffect>

### Контекстные меню и модальные окна

- <doc:ContextMenu>
- <doc:Modal>

### Списки и виртуализация

- <doc:ListView>

### Sheets / Alerts / Overlays

- <doc:ActionSheet>
- <doc:Alert>
- <doc:Toast>
- <doc:Tooltip>

### Bars и toolbars

- <doc:Toolbar>

### Малые контролы

- <doc:SegmentedControl>
- <doc:Skeleton>
- <doc:ContentUnavailable>
