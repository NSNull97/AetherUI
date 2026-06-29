#import "UIView+AetherNavigation.h"
#import <objc/runtime.h>
#import <stdint.h>

static const void *kDisablesInteractiveTransitionGestureRecognizerKey = &kDisablesInteractiveTransitionGestureRecognizerKey;
static const void *kDisablesInteractiveKeyboardGestureRecognizerKey = &kDisablesInteractiveKeyboardGestureRecognizerKey;
static const void *kDisablesInteractiveTransitionGestureRecognizerNowKey = &kDisablesInteractiveTransitionGestureRecognizerNowKey;
static const void *kInteractiveTransitionGestureRecognizerTestKey = &kInteractiveTransitionGestureRecognizerTestKey;
static const void *kInputAccessoryHeightProviderKey = &kInputAccessoryHeightProviderKey;

static NSString *AetherDecodeSymbol(const uint8_t *bytes, NSUInteger length) {
    uint8_t decoded[length];
    for (NSUInteger i = 0; i < length; i++) {
        decoded[i] = bytes[i] ^ 0x5A;
    }
    return [[NSString alloc] initWithBytes:decoded length:length encoding:NSUTF8StringEncoding];
}

static NSString *AetherKeyboardWindowClassName(void) {
    static const uint8_t bytes[] = {
        0x0f, 0x13, 0x08, 0x3f, 0x37, 0x35, 0x2e, 0x3f, 0x11, 0x3f, 0x23,
        0x38, 0x35, 0x3b, 0x28, 0x3e, 0x0d, 0x33, 0x34, 0x3e, 0x35, 0x2d
    };
    return AetherDecodeSymbol(bytes, sizeof(bytes));
}

static NSString *AetherKeyboardWindowSelectorName(void) {
    static const uint8_t bytes[] = {
        0x28, 0x3f, 0x37, 0x35, 0x2e, 0x3f, 0x11, 0x3f, 0x23, 0x38, 0x35,
        0x3b, 0x28, 0x3e, 0x0d, 0x33, 0x34, 0x3e, 0x35, 0x2d, 0x1c, 0x35,
        0x28, 0x09, 0x39, 0x28, 0x3f, 0x3f, 0x34, 0x60, 0x39, 0x28, 0x3f,
        0x3b, 0x2e, 0x3f, 0x60
    };
    return AetherDecodeSymbol(bytes, sizeof(bytes));
}

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

@implementation UIApplication (AetherKeyboardRuntime)

- (UIWindow * _Nullable)aether_internalGetKeyboardWindow {
    Class windowClass = NSClassFromString(AetherKeyboardWindowClassName());
    SEL selector = NSSelectorFromString(AetherKeyboardWindowSelectorName());
    if (windowClass == Nil || ![windowClass respondsToSelector:selector]) {
        return nil;
    }
    IMP implementation = [windowClass methodForSelector:selector];
    if (implementation == NULL) {
        return nil;
    }
    typedef UIWindow * _Nullable (*AetherKeyboardWindowFunction)(id, SEL, UIScreen * _Nullable, BOOL);
    AetherKeyboardWindowFunction function = (AetherKeyboardWindowFunction)implementation;
    return function(windowClass, selector, [UIScreen mainScreen], NO);
}

@end
