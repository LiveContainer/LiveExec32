#import <LC32/LC32.h>
#import <UIKit/UIKit.h>

/*
 * UIAccessibility is declared as an NSObject category. These inherited
 * accessors therefore do not appear in the generated method lists for UIKit
 * controls such as UIButton. Bridge the common category surface explicitly so
 * every guest proxy inherits the host peer's accessibility state.
 */
#define LC32_ACCESSIBILITY_OBJECT_PROPERTY(type, getter, setter) \
- (type)getter { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, NO); \
    const uint64_t result = LC32InvokeHostSelector( \
        self.host_self, selector, (uint64_t)0); \
    return LC32HostToGuestObject(result); \
} \
- (void)setter:(type)value { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, NO); \
    LC32InvokeHostSelector(self.host_self, selector, \
                           [(NSObject *)value host_self], (uint64_t)0); \
}

#define LC32_ACCESSIBILITY_INTEGER_PROPERTY(type, getter, setter) \
- (type)getter { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, NO); \
    return (type)LC32InvokeHostSelector( \
        self.host_self, selector, (uint64_t)0); \
} \
- (void)setter:(type)value { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, NO); \
    LC32InvokeHostSelector(self.host_self, selector, \
                           (uint64_t)value, (uint64_t)0); \
}

@implementation NSObject (LC32Accessibility)

LC32_ACCESSIBILITY_OBJECT_PROPERTY(NSString *, accessibilityLabel,
                                   setAccessibilityLabel)
LC32_ACCESSIBILITY_OBJECT_PROPERTY(NSString *, accessibilityHint,
                                   setAccessibilityHint)
LC32_ACCESSIBILITY_OBJECT_PROPERTY(NSString *, accessibilityValue,
                                   setAccessibilityValue)
LC32_ACCESSIBILITY_OBJECT_PROPERTY(NSString *, accessibilityIdentifier,
                                   setAccessibilityIdentifier)
LC32_ACCESSIBILITY_INTEGER_PROPERTY(BOOL, isAccessibilityElement,
                                    setIsAccessibilityElement)
LC32_ACCESSIBILITY_INTEGER_PROPERTY(UIAccessibilityTraits,
                                    accessibilityTraits,
                                    setAccessibilityTraits)

@end
