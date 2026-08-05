#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

static uint64_t LC32InvokeNSStringFormat(id receiver,
                                         uint64_t hostSelector,
                                         NSString *format,
                                         id locale,
                                         va_list arguments,
                                         LC32NSStringFormatOptions options) {
    return LC32InvokeHostNSStringFormat([receiver host_self],
                                        hostSelector,
                                        format.host_self,
                                        [locale host_self],
                                        arguments,
                                        options);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation NSString (LC32Variadic)

+ (instancetype)stringWithFormat:(NSString *)format, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, format);
    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, nil, arguments, 0);
    va_end(arguments);
    return LC32HostToGuestObject(result);
}

+ (instancetype)localizedStringWithFormat:(NSString *)format, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, format);
    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, nil, arguments, 0);
    va_end(arguments);
    return LC32HostToGuestObject(result);
}

+ (instancetype)stringWithFormat:(NSString *)format locale:(id)locale, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, locale);
    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, locale, arguments,
        LC32NSStringFormatOptionHasLocale);
    va_end(arguments);
    return LC32HostToGuestObject(result);
}

- (instancetype)initWithFormat:(NSString *)format, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, format);
    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, nil, arguments, 0);
    va_end(arguments);
    if(!result) return nil;
    self.host_self = result;
    return self;
}

- (instancetype)initWithFormat:(NSString *)format
                      arguments:(va_list)arguments {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, nil, arguments,
        LC32NSStringFormatOptionArgumentsList);
    if(!result) return nil;
    self.host_self = result;
    return self;
}

- (instancetype)initWithFormat:(NSString *)format locale:(id)locale, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, locale);
    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, locale, arguments,
        LC32NSStringFormatOptionHasLocale);
    va_end(arguments);
    if(!result) return nil;
    self.host_self = result;
    return self;
}

- (instancetype)initWithFormat:(NSString *)format
                         locale:(id)locale
                      arguments:(va_list)arguments {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, locale, arguments,
        LC32NSStringFormatOptionHasLocale |
            LC32NSStringFormatOptionArgumentsList);
    if(!result) return nil;
    self.host_self = result;
    return self;
}

- (NSString *)stringByAppendingFormat:(NSString *)format, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, format);
    uint64_t result = LC32InvokeNSStringFormat(
        self, hostSelector, format, nil, arguments, 0);
    va_end(arguments);
    return LC32HostToGuestObject(result);
}

@end

#pragma clang diagnostic pop

@implementation NSMutableString (LC32Variadic)

- (void)appendFormat:(NSString *)format, ... {
    uint64_t hostSelector = LC32GetHostSelector(_cmd);

    va_list arguments;
    va_start(arguments, format);
    LC32InvokeNSStringFormat(self, hostSelector, format, nil, arguments, 0);
    va_end(arguments);
}

@end
