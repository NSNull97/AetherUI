#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C associated-object bag for interactive-gesture opt-outs. Ported from
/// Telegram-iOS `UIKitRuntimeUtils/UIViewController+Navigation.{h,m}` — trimmed
/// down to the pieces AetherUI actually uses (no swizzling, no
/// AboveStatusBarWindow, no private-API status-bar helpers).
///
/// `InteractiveTransitionGestureRecognizer` and `AetherWindow`'s keyboard
/// gesture walk the superview chain to see whether any ancestor has opted
/// out of horizontal-swipe back / interactive keyboard dismissal. Because
/// these are read on every touch, they live directly on `UIView` via
/// associated objects rather than on controllers (which would require an
/// extra hop per frame).
@interface UIView (AetherNavigation)

/// Blocks the swipe-back edge pan when the touch starts inside this view
/// or any ancestor. Set on carousels, horizontal pagers, color pickers,
/// etc. where horizontal drags belong to the subtree.
@property (nonatomic) BOOL disablesInteractiveTransitionGestureRecognizer;

/// Blocks the interactive keyboard-dismiss pan when the touch starts
/// inside this view or any ancestor. Set on sliders / color pickers /
/// anything that needs vertical drags above the keyboard.
@property (nonatomic) BOOL disablesInteractiveKeyboardGestureRecognizer;

/// Dynamic variant of `disablesInteractiveTransitionGestureRecognizer`.
/// Evaluated at touch time — return `YES` to block the gesture. Use when
/// the opt-out depends on state that changes frequently (e.g., a pager
/// that disables the outer gesture only when it has more than one page).
@property (nonatomic, copy, nullable) BOOL (^disablesInteractiveTransitionGestureRecognizerNow)(void);

/// Point-based test block. Evaluated at touch time with the touch point
/// in the view's own coordinate space — return `YES` to block the outer
/// gesture only when the touch falls in a specific region (e.g., an
/// in-view drag handle).
@property (nonatomic, copy, nullable) BOOL (^interactiveTransitionGestureRecognizerTest)(CGPoint);

/// Register a height provider for the interactive keyboard dismiss
/// gesture. Views that sit on top of the keyboard (chat compose bars,
/// reply previews, etc.) report their own height here so the pan
/// recognizer treats the area above them as "belongs to the accessory",
/// not "belongs to the keyboard".
- (void)input_setInputAccessoryHeightProvider:(CGFloat (^ _Nullable)(void))block;
- (CGFloat)input_getInputAccessoryHeight;

@end

/// Walks the superview chain starting from `view`. Returns `YES` if any
/// ancestor opts out of the interactive transition gesture via any of the
/// three mechanisms above (`disables...`, `disables...Now`, or the
/// point-based `interactiveTransitionGestureRecognizerTest` if `point` is
/// supplied).
BOOL AetherViewTreeDisablesInteractiveTransitionGesture(UIView *view, CGPoint point, BOOL hasPoint);

/// Walks the superview chain starting from `view`. Returns `YES` if any
/// ancestor opts out of the interactive keyboard-dismiss gesture.
BOOL AetherViewTreeDisablesInteractiveKeyboardGesture(UIView *view);

NS_ASSUME_NONNULL_END
