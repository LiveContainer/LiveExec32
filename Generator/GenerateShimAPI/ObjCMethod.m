#import "ObjCMethod.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static void LC32MarkInvalid(BOOL *valid) {
    if(valid) *valid = NO;
}

static const char *LC32SkipQuotedString(const char *cursor, BOOL *valid) {
    if(!cursor || *cursor != '"') {
        LC32MarkInvalid(valid);
        return cursor;
    }

    cursor++;
    while(*cursor) {
        if(*cursor == '\\' && cursor[1]) {
            cursor += 2;
        } else if(*cursor++ == '"') {
            return cursor;
        }
    }
    LC32MarkInvalid(valid);
    return cursor;
}

static const char *LC32SkipBalancedType(const char *cursor,
                                        char opening,
                                        char closing,
                                        BOOL *valid) {
    if(!cursor || *cursor != opening) {
        LC32MarkInvalid(valid);
        return cursor;
    }

    NSUInteger depth = 0;
    while(*cursor) {
        if(*cursor == '"') {
            cursor = LC32SkipQuotedString(cursor, valid);
            continue;
        }
        if(*cursor == opening) {
            depth++;
        } else if(*cursor == closing) {
            if(depth == 0) {
                LC32MarkInvalid(valid);
                return cursor;
            }
            if(--depth == 0) return cursor + 1;
        }
        cursor++;
    }
    LC32MarkInvalid(valid);
    return cursor;
}

/// Returns the first byte after one type encoding.
static const char *LC32SkipType(const char *cursor, BOOL *valid) {
    if(!cursor || !*cursor) {
        LC32MarkInvalid(valid);
        return cursor;
    }

    // Objective-C type qualifiers and C complex-number marker.
    while(*cursor && strchr("rnNoORVAj", *cursor)) cursor++;
    if(!*cursor) {
        LC32MarkInvalid(valid);
        return cursor;
    }

    switch(*cursor) {
        case '"':
            return LC32SkipType(LC32SkipQuotedString(cursor, valid), valid);
        case '^': {
            const char *pointee = cursor + 1;
            if(!*pointee || isdigit((unsigned char)*pointee) ||
               *pointee == '+' || *pointee == '-') {
                LC32MarkInvalid(valid);
                return pointee;
            }
            return LC32SkipType(pointee, valid);
        }
        case '@':
            cursor++;
            if(*cursor == '?') return cursor + 1;
            if(*cursor == '"') return LC32SkipQuotedString(cursor, valid);
            return cursor;
        case 'b': {
            cursor++;
            if(!isdigit((unsigned char)*cursor)) {
                LC32MarkInvalid(valid);
                return cursor;
            }
            while(isdigit((unsigned char)*cursor)) cursor++;
            return cursor;
        }
        case '[':
            return LC32SkipBalancedType(cursor, '[', ']', valid);
        case '{':
            return LC32SkipBalancedType(cursor, '{', '}', valid);
        case '(':
            return LC32SkipBalancedType(cursor, '(', ')', valid);
        case '!':
            // Clang vector encodings use ![...] when the runtime preserves
            // them. Some iOS 10 methods omit the vector type entirely.
            if(cursor[1] == '[') {
                return LC32SkipBalancedType(cursor + 1, '[', ']', valid);
            }
            LC32MarkInvalid(valid);
            return cursor + 1;
        default:
            if(!strchr("cislqCISLQfdDBv*@#:?", *cursor)) {
                LC32MarkInvalid(valid);
            }
            return cursor + 1;
    }
}

static BOOL LC32IsCompleteSingleTypeEncoding(const char *encoding) {
    if(!encoding || !*encoding) return NO;
    BOOL valid = YES;
    const char *end = LC32SkipType(encoding, &valid);
    return valid && end && *end == '\0';
}

static void LC32SkipOffset(const char **cursor) {
    if(!cursor || !*cursor) return;
    if(**cursor == '+' || **cursor == '-') (*cursor)++;
    while(isdigit((unsigned char)**cursor)) (*cursor)++;
}

static NSString *LC32StringForTypeRange(const char *start, const char *end) {
    if(!start || !end || end <= start) return nil;
    return [[NSString alloc] initWithBytes:start
                                    length:(NSUInteger)(end - start)
                                  encoding:NSUTF8StringEncoding];
}

static NSUInteger LC32SelectorArgumentCount(SEL selector) {
    const char *name = sel_getName(selector);
    NSUInteger count = 0;
    for(; name && *name; name++) {
        if(*name == ':') count++;
    }
    return count;
}

@interface LC32ObjCMethod ()
@property(nonatomic, assign, readwrite) SEL selector;
@property(nonatomic, copy, readwrite) NSString *selectorString;
@property(nonatomic, assign, readwrite) BOOL isInstanceMethod;
@property(nonatomic, copy, readwrite) NSString *typeEncoding;
@property(nonatomic, copy) NSString *returnTypeStorage;
@property(nonatomic, copy) NSArray<NSString *> *argumentTypes;
@property(nonatomic, assign, readwrite) BOOL hasCompleteTypeEncoding;
@end

@implementation LC32ObjCMethod

+ (instancetype)method:(Method)method
       isInstanceMethod:(BOOL)isInstanceMethod {
    if(!method) return nil;

    SEL selector = method_getName(method);
    const char *typeEncoding = method_getTypeEncoding(method);
    if(!selector || !typeEncoding) return nil;

    LC32ObjCMethod *result = [[self alloc] init];
    result.selector = selector;
    result.selectorString = NSStringFromSelector(selector);
    result.isInstanceMethod = isInstanceMethod;
    result.typeEncoding = @(typeEncoding);

    char *returnType = method_copyReturnType(method);
    result.returnTypeStorage = returnType ? @(returnType) : @"?";
    BOOL complete = LC32IsCompleteSingleTypeEncoding(returnType);
    free(returnType);

    unsigned int runtimeArgumentCount = method_getNumberOfArguments(method);
    NSMutableArray<NSString *> *argumentTypes =
        [NSMutableArray arrayWithCapacity:runtimeArgumentCount];
    for(unsigned int index = 0; index < runtimeArgumentCount; index++) {
        char *argumentType = method_copyArgumentType(method, index);
        if(argumentType && *argumentType) {
            [argumentTypes addObject:@(argumentType)];
            complete = complete &&
                LC32IsCompleteSingleTypeEncoding(argumentType);
        } else {
            [argumentTypes addObject:@"?"];
            complete = NO;
        }
        free(argumentType);
    }

    NSUInteger expectedArgumentCount = LC32SelectorArgumentCount(selector) + 2;
    result.argumentTypes = argumentTypes;
    BOOL implicitArgumentsValid =
        argumentTypes.count >= 2 &&
        [argumentTypes[0] isEqualToString:@"@"] &&
        [argumentTypes[1] isEqualToString:@":"];
    result.hasCompleteTypeEncoding =
        complete && implicitArgumentsValid &&
        runtimeArgumentCount == expectedArgumentCount;
    return result;
}

+ (instancetype)methodWithSelector:(SEL)selector
                       typeEncoding:(const char *)typeEncoding
                   isInstanceMethod:(BOOL)isInstanceMethod {
    if(!selector || !typeEncoding || !*typeEncoding) return nil;

    LC32ObjCMethod *result = [[self alloc] init];
    result.selector = selector;
    result.selectorString = NSStringFromSelector(selector);
    result.isInstanceMethod = isInstanceMethod;
    result.typeEncoding = @(typeEncoding);

    BOOL complete = YES;
    const char *cursor = typeEncoding;
    if(isdigit((unsigned char)*cursor) || *cursor == '+' || *cursor == '-') {
        // A few SIMD methods in the iOS 10 runtime omit their return type.
        result.returnTypeStorage = @"?";
        complete = NO;
    } else {
        BOOL returnTypeValid = YES;
        const char *returnEnd = LC32SkipType(cursor, &returnTypeValid);
        NSString *returnType = LC32StringForTypeRange(cursor, returnEnd);
        result.returnTypeStorage = returnType ? returnType : @"?";
        complete = returnTypeValid && returnEnd && returnEnd > cursor;
        cursor = returnEnd;
    }
    LC32SkipOffset(&cursor);

    NSUInteger expectedArgumentCount = LC32SelectorArgumentCount(selector) + 2;
    NSMutableArray<NSString *> *argumentTypes =
        [NSMutableArray arrayWithCapacity:expectedArgumentCount];
    for(NSUInteger index = 0; index < expectedArgumentCount; index++) {
        if(!*cursor || isdigit((unsigned char)*cursor) ||
           *cursor == '+' || *cursor == '-') {
            [argumentTypes addObject:@"?"];
            complete = NO;
            LC32SkipOffset(&cursor);
            continue;
        }

        BOOL argumentTypeValid = YES;
        const char *argumentEnd = LC32SkipType(cursor, &argumentTypeValid);
        NSString *argumentType = LC32StringForTypeRange(cursor, argumentEnd);
        if(!argumentType.length || !argumentTypeValid) {
            argumentType = @"?";
            complete = NO;
        }
        [argumentTypes addObject:argumentType];
        cursor = argumentEnd;
        LC32SkipOffset(&cursor);
    }

    // Extra non-offset data means our parser and selector disagree.
    if(*cursor) complete = NO;
    if(argumentTypes.count < 2 ||
       ![argumentTypes[0] isEqualToString:@"@"] ||
       ![argumentTypes[1] isEqualToString:@":"]) {
        complete = NO;
    }

    result.argumentTypes = argumentTypes;
    result.hasCompleteTypeEncoding = complete;
    return result;
}

- (NSUInteger)numberOfArguments {
    return self.argumentTypes.count;
}

- (const char *)returnType {
    const char *returnType = self.returnTypeStorage.UTF8String;
    return returnType ? returnType : "?";
}

- (const char *)argumentTypeAtIndex:(NSUInteger)index {
    if(index >= self.argumentTypes.count) return "?";
    const char *argumentType = self.argumentTypes[index].UTF8String;
    return argumentType ? argumentType : "?";
}

- (NSString *)description {
    NSString *prefix = self.isInstanceMethod ? @"-" : @"+";
    NSString *returnType = LC32ReadableTypeForEncoding(self.returnType);
    NSMutableString *description =
        [NSMutableString stringWithFormat:@"%@ (%@)", prefix, returnType];

    if(self.numberOfArguments <= 2) {
        [description appendString:self.selectorString];
        return description;
    }

    NSArray<NSString *> *selectorComponents =
        [self.selectorString componentsSeparatedByString:@":"];
    for(NSUInteger index = 2; index < self.numberOfArguments; index++) {
        NSUInteger componentIndex = index - 2;
        NSString *component = componentIndex < selectorComponents.count
            ? selectorComponents[componentIndex]
            : [NSString stringWithFormat:@"argument%lu",
               (unsigned long)componentIndex];
        NSString *type =
            LC32ReadableTypeForEncoding([self argumentTypeAtIndex:index]);
        if(index > 2) [description appendString:@" "];
        [description appendFormat:@"%@:(%@)", component, type];
    }
    return description;
}

@end

static NSString *LC32ReadableObjectType(const char *encoding) {
    if(encoding[1] == '\0' || encoding[1] == '?') return @"id";
    if(encoding[1] != '"') return @"id";

    const char *end = strchr(encoding + 2, '"');
    if(!end) return @"id";
    NSString *name = LC32StringForTypeRange(encoding + 2, end);
    if(!name.length) return @"id";
    if([name hasPrefix:@"<"] && [name hasSuffix:@">"]) {
        return [@"id" stringByAppendingString:name];
    }
    return [name stringByAppendingString:@" *"];
}

NSString *LC32ReadableTypeForEncoding(const char *encoding) {
    if(!encoding || !*encoding) return @"?";

    if(*encoding == '"') {
        BOOL valid = YES;
        const char *afterName = LC32SkipQuotedString(encoding, &valid);
        if(!valid) return @"?";
        NSString *name = LC32StringForTypeRange(encoding + 1, afterName - 1);
        NSString *type = LC32ReadableTypeForEncoding(afterName);
        return name.length ? [NSString stringWithFormat:@"%@ %@", type, name]
                           : type;
    }

    switch(*encoding) {
        case '@':
            return LC32ReadableObjectType(encoding);
        case '^':
            return [NSString stringWithFormat:@"%@ *",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'r':
            return [NSString stringWithFormat:@"const %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'n':
            return [NSString stringWithFormat:@"in %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'N':
            return [NSString stringWithFormat:@"inout %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'o':
            return [NSString stringWithFormat:@"out %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'O':
            return [NSString stringWithFormat:@"bycopy %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'R':
            return [NSString stringWithFormat:@"byref %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'V':
            return [NSString stringWithFormat:@"oneway %@",
                    LC32ReadableTypeForEncoding(encoding + 1)];
        case 'b':
            return [NSString stringWithFormat:@"bitfield(%s)", encoding + 1];
        case 'B': return @"BOOL";
        case 'C': return @"unsigned char";
        case 'I': return @"unsigned int";
        case 'L': return @"uint32_t";
        case 'Q': return @"unsigned long long";
        case 'S': return @"unsigned short";
        case 'c': return @"char";
        case 'd': return @"double";
        case 'f': return @"float";
        case 'i': return @"int";
        case 'l': return @"int32_t";
        case 'q': return @"long long";
        case 's': return @"short";
        case 'D': return @"long double";
        case 'v': return @"void";
        case '*': return @"char *";
        case '#': return @"Class";
        case ':': return @"SEL";
        case '?': return @"?";
        case '{': {
            const char *nameStart = encoding + 1;
            const char *equals = strchr(nameStart, '=');
            if(!equals) return @(encoding);
            if(nameStart[0] == '?') return @"anonymous struct";
            NSString *name = LC32StringForTypeRange(nameStart, equals);
            return name ? name : @(encoding);
        }
        default:
            return @(encoding);
    }
}
