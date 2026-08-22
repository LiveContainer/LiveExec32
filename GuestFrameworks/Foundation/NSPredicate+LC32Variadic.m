#import <Foundation/Foundation.h>

#include <stdarg.h>

/*
 * Objective-C method encodings do not describe the ellipsis in
 * +predicateWithFormat:.  The generated fixed-argument bridge therefore
 * cannot forward its ARMv7 va_list to arm64 Foundation.  Consume the
 * object substitutions in the guest and use the fixed-argument
 * argumentArray: entry point instead.
 *
 * Object and key-path substitutions are the only forms which can be
 * decoded without knowing a promoted scalar's type.  Refuse other
 * conversions rather than consuming the guest va_list with the wrong ABI.
 */
@implementation NSPredicate (LC32Variadic)

+ (NSPredicate *)predicateWithFormat:(NSString *)format, ... {
    if(!format) {
        [NSException raise:NSInvalidArgumentException
                    format:@"predicate format must not be nil"];
    }

    const char *bytes = format.UTF8String;
    if(!bytes) return nil;

    NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:4];
    va_list list;
    va_start(list, format);

    BOOL supported = YES;
    for(const unsigned char *cursor = (const unsigned char *)bytes;
            *cursor; cursor++) {
        if(*cursor != '%') continue;
        cursor++;
        if(*cursor == '%') continue;
        if(*cursor == '@' || *cursor == 'K') {
            id argument = va_arg(list, id);
            [arguments addObject:argument ?: [NSNull null]];
            continue;
        }
        supported = NO;
        break;
    }

    va_end(list);
    if(!supported) {
        [NSException raise:NSInvalidArgumentException
                    format:@"unsupported predicate substitution in %@",
                           format];
    }
    return [self predicateWithFormat:format argumentArray:arguments];
}

@end
