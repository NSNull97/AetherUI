#import "UIView+AetherNavigation.h"
#import <objc/runtime.h>

static const void *kDisablesInteractiveTransitionGestureRecognizerKey = &kDisablesInteractiveTransitionGestureRecognizerKey;
static const void *kDisablesInteractiveKeyboardGestureRecognizerKey = &kDisablesInteractiveKeyboardGestureRecognizerKey;
static const void *kDisablesInteractiveTransitionGestureRecognizerNowKey = &kDisablesInteractiveTransitionGestureRecognizerNowKey;
static const void *kInteractiveTransitionGestureRecognizerTestKey = &kInteractiveTransitionGestureRecognizerTestKey;
static const void *kInputAccessoryHeightProviderKey = &kInputAccessoryHeightProviderKey;

@implementation UIView (AetherNavigation)

- (BOOL)disablesInteractiveTransitionGestureRecognizer {
    return [objc_getAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerKey) boolValue];
}

- (void)setDisablesInteractiveTransitionGestureRecognizer:(BOOL)value {
    objc_setAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)disablesInteractiveKeyboardGestureRecognizer {
    return [objc_getAssociatedObject(self, kDisablesInteractiveKeyboardGestureRecognizerKey) boolValue];
}

- (void)setDisablesInteractiveKeyboardGestureRecognizer:(BOOL)value {
    objc_setAssociatedObject(self, kDisablesInteractiveKeyboardGestureRecognizerKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL (^)(void))disablesInteractiveTransitionGestureRecognizerNow {
    return objc_getAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerNowKey);
}

- (void)setDisablesInteractiveTransitionGestureRecognizerNow:(BOOL (^)(void))block {
    objc_setAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerNowKey, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL (^)(CGPoint))interactiveTransitionGestureRecognizerTest {
    return objc_getAssociatedObject(self, kInteractiveTransitionGestureRecognizerTestKey);
}

- (void)setInteractiveTransitionGestureRecognizerTest:(BOOL (^)(CGPoint))block {
    objc_setAssociatedObject(self, kInteractiveTransitionGestureRecognizerTestKey, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)input_setInputAccessoryHeightProvider:(CGFloat (^)(void))block {
    objc_setAssociatedObject(self, kInputAccessoryHeightProviderKey, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)input_getInputAccessoryHeight {
    CGFloat (^block)(void) = objc_getAssociatedObject(self, kInputAccessoryHeightProviderKey);
    if (block != nil) {
        return block();
    }
    return 0.0;
}

@end

BOOL AetherViewTreeDisablesInteractiveTransitionGesture(UIView *view, CGPoint point, BOOL hasPoint) {
    UIView *current = view;
    CGPoint currentPoint = point;
    while (current != nil) {
        if (current.disablesInteractiveTransitionGestureRecognizer) {
            return YES;
        }
        BOOL (^now)(void) = current.disablesInteractiveTransitionGestureRecognizerNow;
        if (now != nil && now()) {
            return YES;
        }
        if (hasPoint) {
            BOOL (^test)(CGPoint) = current.interactiveTransitionGestureRecognizerTest;
            if (test != nil && test(currentPoint)) {
                return YES;
            }
        }
        UIView *superview = current.superview;
        if (superview != nil && hasPoint) {
            currentPoint = [current convertPoint:currentPoint toView:superview];
        }
        current = superview;
    }
    return NO;
}

BOOL AetherViewTreeDisablesInteractiveKeyboardGesture(UIView *view) {
    UIView *current = view;
    while (current != nil) {
        if (current.disablesInteractiveKeyboardGestureRecognizer) {
            return YES;
        }
        current = current.superview;
    }
    return NO;
}
