#import <LC32/LC32.h>
#import <UIKit/UIKit.h>

/*
 * UITextInputTraits consists entirely of optional protocol methods. UIKit's
 * concrete text controls respond to them, but the accessors are not present
 * in the class-local method lists captured by GenerateMethodSignatures. Keep
 * the iOS 10 public trait surface here so subclasses (including third-party
 * UITextField subclasses) inherit working bridge methods.
 */
#define LC32_TEXT_INPUT_INTEGER_GETTER(type, getter) \
- (type)getter { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, 0); \
    return (type)LC32InvokeHostSelector( \
        self.host_self, selector, (uint64_t)0); \
}

#define LC32_TEXT_INPUT_INTEGER_SETTER(type, setter) \
- (void)setter:(type)value { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, 0); \
    LC32InvokeHostSelector(self.host_self, selector, \
                           (uint64_t)value, (uint64_t)0); \
}

#define LC32_TEXT_INPUT_INTEGER_PROPERTY(type, getter, setter) \
LC32_TEXT_INPUT_INTEGER_GETTER(type, getter) \
LC32_TEXT_INPUT_INTEGER_SETTER(type, setter)

#define LC32_TEXT_INPUT_BOOL_GETTER(getter) \
LC32_TEXT_INPUT_INTEGER_GETTER(BOOL, getter)

#define LC32_TEXT_INPUT_BOOL_PROPERTY(getter, setter) \
LC32_TEXT_INPUT_INTEGER_PROPERTY(BOOL, getter, setter)

#define LC32_TEXT_INPUT_OBJECT_PROPERTY(type, getter, setter) \
- (type)getter { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, 0); \
    return (type)LC32InvokeHostObjectSelector( \
        self.host_self, selector, (uint64_t)0); \
} \
- (void)setter:(type)value { \
    static uint64_t hostSelector; \
    const uint64_t selector = LC32CachedHostSelector( \
        &hostSelector, _cmd, 0); \
    LC32InvokeHostSelector(self.host_self, selector, \
                           [value host_self], (uint64_t)0); \
}

#define LC32_TEXT_INPUT_COMMON_PROPERTIES \
LC32_TEXT_INPUT_INTEGER_PROPERTY(UITextAutocapitalizationType, \
                                 autocapitalizationType, \
                                 setAutocapitalizationType) \
LC32_TEXT_INPUT_INTEGER_PROPERTY(UITextAutocorrectionType, \
                                 autocorrectionType, \
                                 setAutocorrectionType) \
LC32_TEXT_INPUT_INTEGER_PROPERTY(UITextSpellCheckingType, \
                                 spellCheckingType, \
                                 setSpellCheckingType) \
LC32_TEXT_INPUT_INTEGER_PROPERTY(UIKeyboardType, \
                                 keyboardType, \
                                 setKeyboardType) \
LC32_TEXT_INPUT_INTEGER_PROPERTY(UIReturnKeyType, \
                                 returnKeyType, \
                                 setReturnKeyType) \
LC32_TEXT_INPUT_BOOL_PROPERTY(enablesReturnKeyAutomatically, \
                              setEnablesReturnKeyAutomatically) \
LC32_TEXT_INPUT_OBJECT_PROPERTY(UITextContentType, \
                                textContentType, \
                                setTextContentType)

@implementation UITextField (LC32TextInputTraits)
LC32_TEXT_INPUT_COMMON_PROPERTIES
LC32_TEXT_INPUT_INTEGER_GETTER(UIKeyboardAppearance, keyboardAppearance)
LC32_TEXT_INPUT_BOOL_GETTER(isSecureTextEntry)
@end

@implementation UITextView (LC32TextInputTraits)
LC32_TEXT_INPUT_COMMON_PROPERTIES
LC32_TEXT_INPUT_INTEGER_PROPERTY(UIKeyboardAppearance,
                                 keyboardAppearance,
                                 setKeyboardAppearance)
LC32_TEXT_INPUT_BOOL_GETTER(isSecureTextEntry)
@end

@implementation UISearchBar (LC32TextInputTraits)
LC32_TEXT_INPUT_COMMON_PROPERTIES
LC32_TEXT_INPUT_INTEGER_GETTER(UIKeyboardAppearance, keyboardAppearance)
LC32_TEXT_INPUT_BOOL_PROPERTY(isSecureTextEntry, setSecureTextEntry)
@end
