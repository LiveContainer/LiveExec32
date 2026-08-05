@import Darwin;
@import QuartzCore;
@import CoreFoundation;
@import Foundation;
@import UIKit;
@import ObjectiveC;

#import "ObjCMethod.h"

#include <string.h>

typedef NS_ENUM(NSUInteger, LC32KnownStruct) {
    LC32KnownStructNone,
    LC32KnownStructCGAffineTransform,
    LC32KnownStructCGPoint,
    LC32KnownStructCGRect,
    LC32KnownStructCGSize,
    LC32KnownStructUIEdgeInsets,
};

static LC32KnownStruct LC32KnownStructForEncoding(const char *encoding) {
    if(!encoding) return LC32KnownStructNone;

    while(*encoding && strchr("rnNoORVA", *encoding)) encoding++;
    if(!strncmp(encoding, "{CGAffineTransform=", sizeof("{CGAffineTransform=") - 1)) {
        return LC32KnownStructCGAffineTransform;
    }
    if(!strncmp(encoding, "{CGPoint=", sizeof("{CGPoint=") - 1)) {
        return LC32KnownStructCGPoint;
    }
    if(!strncmp(encoding, "{CGRect=", sizeof("{CGRect=") - 1)) {
        return LC32KnownStructCGRect;
    }
    if(!strncmp(encoding, "{CGSize=", sizeof("{CGSize=") - 1)) {
        return LC32KnownStructCGSize;
    }
    if(!strncmp(encoding, "{UIEdgeInsets=", sizeof("{UIEdgeInsets=") - 1)) {
        return LC32KnownStructUIEdgeInsets;
    }
    return LC32KnownStructNone;
}

@interface MethodParameter : NSObject
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *type;
@property(nonatomic, assign) const char *signature;
// index from 0
@property(nonatomic) int index;
@end
@implementation MethodParameter

// FIXME: will need to parse header to return correctly. On 64bit, NS*Integer and CGFloat are not distinguishable from 32bit
+ (NSString *)readableTypeForSignature:(const char *)signature {
    if(!signature || !*signature) return @"?";

    // Correct some 32bit types
    if(signature[0] == '^' && signature[1]) {
        switch(signature[1]) {
            case 'L':
                return @"uint32_t *";
            case 'Q':
                return @"uint64_t *";
            case 'c':
                return @"BOOL *";
            case 'd':
                return @"double *";
            case 'l':
                return @"int32_t *";
            case 'q':
                return @"int64_t *";
        }
    }

    switch(signature[0]) {
        case 'C':
            return @"unsigned char";
        case 'L':
            return @"uint32_t";
        case 'Q':
            return @"uint64_t";
        case 'c':
            return @"char";
        case 'd':
            return @"double";
        case 'l':
            return @"int32_t";
        case 'q':
            return @"int64_t";
        default:
            return LC32ReadableTypeForEncoding(signature);
    }
}

+ (BOOL)isDirectCastType:(char)c {
    switch(c) {
        case 'B':
        case 'C':
        case 'I':
        case 'L':
        case 'Q':
        case 'S':
        case 'b':
        case 'c':
        case 'i':
        case 'l':
        case 'q':
        case 's':
            return YES;
    }
    return NO;
}

+ (BOOL)isFloatingType:(char)c {
    return c == 'd'|| c == 'f';
}

- (instancetype)initWithIndex:(int)index name:(NSString *)name type:(NSString *)type signature:(const char *)signature {
    self = [super init];
    self.index = index;
    self.name = name;
    self.type = type;
    self.signature = signature;
    return self;
}

- (NSString *)declarationInMethod {
    if ([self.type isEqualToString:@"_NSZone *"]) {
        return [NSString stringWithFormat:@"%@:(struct %@)guest_arg%d", self.name, self.type, self.index];
    }
    return [NSString stringWithFormat:@"%@:(%@)guest_arg%d", self.name, self.type, self.index];
}

- (NSString *)declaration {
    if([MethodParameter isDirectCastType:self.signature[0]]) {
        return [NSString stringWithFormat:@"uint64_t host_arg%1$d = (uint64_t)guest_arg%1$d;", self.index];
    } else if([MethodParameter isFloatingType:self.signature[0]]) {
        return [NSString stringWithFormat:@"double host_arg%1$d = (double)guest_arg%1$d;", self.index];
    }
    switch(self.signature[0]) {
        case '@':
        case '#':
            return [NSString stringWithFormat:@"uint64_t host_arg%1$d = [guest_arg%1$d host_self];", self.index];
        case ':':
            return [NSString stringWithFormat:@"uint64_t host_arg%1$d = LC32GetHostSelector(guest_arg%1$d);", self.index];
        case '^':
            if(self.signature[1] == '@' || [MethodParameter isDirectCastType:self.signature[1]]) {
                return [NSString stringWithFormat:@"uint64_t host_arg%d; // %@", self.index, self.type];
            } else if ([self.type isEqualToString:@"_NSZone *"]) {
                return [NSString stringWithFormat:@"uint64_t host_arg%d = 0;", self.index];
            }
            // FIXME ???? else if([MethodParameter isFloatingType:self.signature[0]]) {
            break;
        case 'r': // const
            switch(self.signature[1]) {
                case '*':
                    return [NSString stringWithFormat:@"uint64_t host_arg%1$d = LC32GuestToHostCString(guest_arg%1$d, 0);", self.index];
                //case 'v':
                //    return [NSString stringWithFormat:@"uint64_t host_arg%1$d = 0; // FIXME: LC32GuestToHostCBuffer(guest_arg%1$d, length?);", self.index]; // FIXME
            }
    }

    if(LC32KnownStructForEncoding(self.signature) != LC32KnownStructNone) {
        return [NSString stringWithFormat:@"%1$@_64 host_arg%2$d = LC32Host%1$@(guest_arg%2$d);", self.type, self.index];
        //return [NSString stringWithFormat:@"%1$@_64 host_arg%2$d_value = LC32Host%1$@(guest_arg%2$d); uint64_t host_arg%2$d = LC32GuestToHostCString((const char *)&host_arg%2$d_value, sizeof(host_arg%2$d_value));", self.type, self.index];
    }

    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
}

- (NSString *)parameterToBePassed {
    BOOL returnDirect = NO;
    BOOL returnPointer = NO;
    switch(self.signature[0]) {
        case '@':
        case '#':
        case ':':
            returnDirect = YES;
            break;
        case '^':
            returnPointer = self.signature[1] == '@' || [MethodParameter isDirectCastType:self.signature[1]];
            returnDirect |= [self.type isEqualToString:@"_NSZone *"];
            break;
        case 'r':
            // const char *, void too?
            returnDirect = self.signature[1] == '*';
            break;
        default:
            returnDirect = [MethodParameter isDirectCastType:self.signature[0]] || [MethodParameter isFloatingType:self.signature[0]];
            break;
    }

    if(LC32KnownStructForEncoding(self.signature) != LC32KnownStructNone) {
        returnDirect = YES;
    }

    if(returnDirect) {
        return [NSString stringWithFormat:@"host_arg%d", self.index];
    } else if(returnPointer) {
        return [NSString stringWithFormat:@"&host_arg%d", self.index];
    }
    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
}

- (NSString *)postCall {
    switch(self.signature[0]) {
        case 'r':
            switch(self.signature[1]) {
                case '*':
                    // the string might have been copied, in this case invoke back to the host to free them just in case
                    return [NSString stringWithFormat:@"LC32GuestToHostCStringFree(host_arg%1$d);", self.index];
                //default: fallthrough
            }
        case '*':
            // Handle char *modification??
            return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
        //case '{':
        //    return [NSString stringWithFormat:@"LC32GuestToHostCStringFree(host_arg%1$d);", self.index];
        case '^':
            // handle it below
            if(![self.type isEqualToString:@"_NSZone *"]) {
                break;
            }
            // NSZone: fallthough
        default:
            return [NSString stringWithFormat:@"// No post-process for guest_arg%d", self.index];
    }
    switch(self.signature[1]) {
        case '@': // id **
        case '#': // class **
            return [NSString stringWithFormat:@"*guest_arg%1$d = LC32HostToGuestObject(host_arg%1$d);", self.index];
        default:
            // int*, float *, etc
            if([MethodParameter isDirectCastType:self.signature[1]] &&
               [self.type hasSuffix:@" *"]) {
                NSString *pointeeType =
                    [self.type substringToIndex:self.type.length - 2];
                return [NSString stringWithFormat:
                    @"*guest_arg%1$d = (%2$@)host_arg%1$d;",
                    self.index, pointeeType];
            }
            break;
    }
    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
}

- (NSString *)description {
    return self.declarationInMethod;
}
@end

static BOOL LC32MethodIsInInitFamily(LC32ObjCMethod *method) {
    if(!method.isInstanceMethod) return NO;

    const char *selectorName = sel_getName(method.selector);
    if(!selectorName || strncmp(selectorName, "init", 4) != 0) return NO;

    char next = selectorName[4];
    return next == '\0' || next < 'a' || next > 'z';
}

@interface MethodBuilder : NSObject
@property(nonatomic, retain) LC32ObjCMethod *method;
@property(nonatomic, retain) NSString *returnType;
@property(nonatomic, retain) NSMutableArray<MethodParameter *> *parameters;
@property(nonatomic, retain) NSMutableArray<NSString *> *lines;
@property(nonatomic) BOOL skip;
@end
@implementation MethodBuilder

- (instancetype)initWithMethod:(LC32ObjCMethod *)method {
    self = [super init];
    self.lines = [NSMutableArray new];
    self.parameters = [NSMutableArray new];
    self.method = method;
    const char *returnType = self.method.returnType;
    self.returnType =
        [MethodParameter readableTypeForSignature:returnType ? returnType : ""];

    SEL selector = method.selector;
    NSArray<NSString *> *selectorParameters = [@(sel_getName(selector)) componentsSeparatedByString:@":"];
    for(NSUInteger i = 2; i < self.method.numberOfArguments; i++) {
        const char *argType = [self.method argumentTypeAtIndex:i];
        if(!argType) argType = "?";
        NSString *arg = [MethodParameter readableTypeForSignature:argType];
        NSUInteger selectorIndex = i - 2;
        NSString *name = selectorIndex < selectorParameters.count
            ? selectorParameters[selectorIndex]
            : [NSString stringWithFormat:@"argument%lu", (unsigned long)selectorIndex];
        [self.parameters addObject:[[MethodParameter alloc]
            initWithIndex:(int)selectorIndex
                     name:name
                     type:arg
                signature:argType]];
    }

    // declare method
    //[self.lines addObject:[NSString stringWithFormat:@"// %@", self.method.description]];
    [self.lines addObject:[NSString stringWithFormat:@"%@ {", self.prettyName]];

    // debug: log calls
    [self.lines addObject:@"  printf(\"DBG: call [%s %s]\\n\", class_getName(self.class), sel_getName(_cmd));"];

    // pull host selector
    [self.lines addObject:[NSString stringWithFormat:@"  static uint64_t _host_cmd;"]];
    [self.lines addObject:[NSString stringWithFormat:@"  if(!_host_cmd) _host_cmd = LC32GetHostSelector(_cmd) | (uint64_t)%d << 63;", self.method.returnType[0] == '{']];

    // pull host objects
    for(MethodParameter *param in self.parameters) {
        [self.lines addObject:[NSString stringWithFormat:@"  %@", param.declaration]];
    }

    // perform selector
    [self.lines addObject:[NSString stringWithFormat:@"  %@", self.callLine]];

    // post-call: eg set NSError pointer
    for(MethodParameter *param in self.parameters) {
        [self.lines addObject:[NSString stringWithFormat:@"  %@", param.postCall]];
    }

    // Return value
    [self.lines addObject:[NSString stringWithFormat:@"  %@", self.returnLine]];

    // End
    [self.lines addObject:@"}"];

    if([self.description containsString:@"unhandled type"]) {
        [self.lines insertObject:@"#if 0 // FIXME: has unhandled types" atIndex:0];
        [self.lines addObject:@"#endif"];
    }
    return self;
}

- (NSString *)prettyName {
    NSString *methodTypeString = self.method.isInstanceMethod ? @"-" : @"+";
    NSString *prettyName = [NSString stringWithFormat:@"%@ (%@)", methodTypeString, self.returnType];

    if (self.method.numberOfArguments > 2) {
        return [prettyName stringByAppendingString:[self.parameters componentsJoinedByString:@" "]];
    } else {
        return [prettyName stringByAppendingString:self.method.selectorString];
    }
}

- (NSString *)callLine {
    NSMutableString *call = [NSMutableString new];
    if(self.method.returnType[0] == '{') {
        [call appendFormat:@"%@_64 host_ret; LC32InvokeHostSelector(self.host_self, _host_cmd, &host_ret, sizeof(host_ret)", self.returnType];
    } else {
        [call appendString:@"uint64_t host_ret = LC32InvokeHostSelector(self.host_self, _host_cmd"];
    }
    for(MethodParameter *param in self.parameters) {
        [call appendFormat:@", %@", param.parameterToBePassed];
    }
    // Add a null last arg
    [call appendString:@", 0);"];
    return call;
}

- (NSString *)returnLine {
    switch(self.method.returnType[0]) {
        case 'v':
            if([self.method.selectorString isEqualToString:@"dealloc"]) {
                return @"[super dealloc];";
            } else {
                return @"// return void";
            }
        case '@':
        case '#':
            if(LC32MethodIsInInitFamily(self.method)) {
                return @"self.host_self = host_ret; return self;";
            } else {
                return @"return LC32HostToGuestObject(host_ret);";
            }
        case 'B':
        case 'C':
        case 'I':
        case 'L':
        case 'Q':
        case 'S':
        case 'b':
        case 'c':
        case 'd':
        case 'f':
        case 'i':
        case 'l':
        case 'q':
        case 's':
            return [NSString stringWithFormat:@"return (%@)host_ret;", self.returnType];
    }
    
    if(LC32KnownStructForEncoding(self.method.returnType) != LC32KnownStructNone) {
        return [NSString stringWithFormat:@"return LC32Guest%@(host_ret);", self.returnType];
    }

    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.returnType];
}

- (NSString *)description {
    return [self.lines componentsJoinedByString:@"\n"];
}
@end

@interface ClassBuilder : NSObject
@property(nonatomic, retain) NSMutableDictionary<NSString *, id> *methods;
@property(nonatomic, retain) NSString *className;
@property(nonatomic, retain) NSString *imagePath;
@property(nonatomic) BOOL usesRuntimeSignatures;
@property(nonatomic) NSUInteger skippedIncompleteMethods;
@property(nonatomic) NSUInteger skippedFilteredMethods;
@end
@implementation ClassBuilder
- (instancetype)initWithClass:(Class)cls imagePath:(NSString *)imagePath {
    self = [super init];
    if(!self || !cls) return nil;

    self.className = NSStringFromClass(cls);
    self.imagePath = imagePath;
    self.usesRuntimeSignatures = YES;
    self.methods = [NSMutableDictionary new];

    unsigned int mc = 0;
    Method *mlist;

    mlist = class_copyMethodList(object_getClass(cls), &mc);
    for(unsigned int m = 0; m < mc; m++) {
        [self validateAndAddRuntimeMethod:mlist[m] isInstanceMethod:NO];
    }
    free(mlist);

    mlist = class_copyMethodList(cls, &mc);
    for(unsigned int m = 0; m < mc; m++) {
        [self validateAndAddRuntimeMethod:mlist[m] isInstanceMethod:YES];
    }
    free(mlist);

    return self;
}

- (instancetype)initWithClassName:(NSString *)className
                        imagePath:(NSString *)imagePath
                 methodSignatures:(NSDictionary *)dict {
    self = [super init];
    if(!self) return nil;

    self.className = className;
    self.imagePath = imagePath;
    if([imagePath.lastPathComponent isEqualToString:@"OpenGLES"]) {
        self.imagePath = @"GLKit";
    }
    self.methods = [NSMutableDictionary new];

    for(NSString *kind in @[@"+", @"-"]) {
        NSDictionary *methods = dict[kind];
        BOOL isInstanceMethod = [kind isEqualToString:@"-"];
        for(NSString *selectorName in
                [methods.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *typeEncoding = methods[selectorName];
            LC32ObjCMethod *method = [LC32ObjCMethod
                methodWithSelector:NSSelectorFromString(selectorName)
                      typeEncoding:typeEncoding.UTF8String
                  isInstanceMethod:isInstanceMethod];
            [self validateAndAddMethod:method];
        }
    }

    return self;
}

- (void)validateAndAddRuntimeMethod:(Method)objcMethod
                  isInstanceMethod:(BOOL)isInstanceMethod {
    [self validateAndAddMethod:[LC32ObjCMethod method:objcMethod
                                    isInstanceMethod:isInstanceMethod]];
}

- (void)validateAndAddMethod:(LC32ObjCMethod *)method {
    if(!method) {
        self.skippedIncompleteMethods++;
        return;
    }

    const char *selectorName = sel_getName(method.selector);
    if(strchr(selectorName, '_') != NULL) {
        // this is a private API, skip
        self.skippedFilteredMethods++;
        return;
    } else if(!strcmp(selectorName, "allocWithZone:")) {
        // skip alloc
        self.skippedFilteredMethods++;
        return;
    } else if(!strcmp(selectorName, "dealloc") ||
              !strcmp(selectorName, "autorelease") ||
              !strcmp(selectorName, "release") ||
              !strcmp(selectorName, "retain") ||
              !strcmp(selectorName, "retainCount")) {
        // skip ARC methods
        self.skippedFilteredMethods++;
        return;
    }

    if(!method.hasCompleteTypeEncoding) {
        fprintf(stderr, "Skipping incomplete encoding: %s %s\n",
                self.className.UTF8String, selectorName);
        self.skippedIncompleteMethods++;
        return;
    }

    NSString *methodKey = [NSString stringWithFormat:@"%@%s",
        method.isInstanceMethod ? @"-" : @"+", selectorName];
    if(!method.isInstanceMethod &&
       sel_isEqual(method.selector, @selector(initialize))) {
        // For +(void)initialize, we must first obtain the host class pointer
        NSMutableString *string = [NSMutableString new];
        [string appendFormat:@"%@ {\n", method.description];
        //[string appendString:@"  self.host_self = LC32GetHostClass(class_getName(self.class));\n"];
        [string appendFormat:@"}"];
        self.methods[methodKey] = string;
        return;
    }

    self.methods[methodKey] = [[MethodBuilder alloc] initWithMethod:method];
}

- (NSString *)description {
    NSMutableString *string = [NSMutableString new];
    [string appendString:@"// Generated file\n"];
    if(self.usesRuntimeSignatures) {
        [string appendString:@"// WARNING: types came from the current 64-bit host runtime; audit width-dependent types before using this shim.\n"];
    }
    [string appendFormat:@"#if __has_include(<%1$@/%1$@+LC32.h>)\n", self.imagePath.lastPathComponent];
    [string appendFormat:@"#import <%1$@/%1$@+LC32.h>\n", self.imagePath.lastPathComponent];
    [string appendFormat:@"#else\n"];
    [string appendFormat:@"#import <%1$@/%1$@.h>\n", self.imagePath.lastPathComponent];
    [string appendFormat:@"#endif\n"];
    [string appendFormat:@"#import <LC32/LC32.h>\n"];
    [string appendFormat:@"#import <CoreGraphics/CoreGraphics+LC32.h>\n"];
    [string appendFormat:@"#import <UIKit/UIKit+LC32.h>\n"];
    [string appendFormat:@"@implementation %@\n", self.className];
    NSArray<NSString *> *methodKeys =
        [self.methods.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *methodSources =
        [NSMutableArray arrayWithCapacity:methodKeys.count];
    for(NSString *methodKey in methodKeys) {
        [methodSources addObject:[self.methods[methodKey] description]];
    }
    [string appendString:[methodSources componentsJoinedByString:@"\n\n"]];
    [string appendString:@"\n"];
    [string appendString:@"@end"];
    return string;
}
@end

static BOOL LC32CreateEmptyOutputDirectory(NSString *outputPath,
                                           NSError **error) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if([fileManager fileExistsAtPath:outputPath isDirectory:&isDirectory]) {
        if(!isDirectory) {
            if(error) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteFileExistsError
                                         userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"Output path exists and is not a directory"
                }];
            }
            return NO;
        }

        NSArray *contents = [fileManager contentsOfDirectoryAtPath:outputPath
                                                              error:error];
        if(!contents) return NO;
        if(contents.count != 0) {
            if(error) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteFileExistsError
                                         userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"Output directory must be empty"
                }];
            }
            return NO;
        }
        return YES;
    }

    return [fileManager createDirectoryAtPath:outputPath
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:error];
}

static BOOL LC32IsSafePathComponent(NSString *component) {
    if(![component isKindOfClass:NSString.class] || component.length == 0) {
        return NO;
    }
    if([component isEqualToString:@"."] ||
       [component isEqualToString:@".."]) {
        return NO;
    }
    return [component rangeOfString:@"/"].location == NSNotFound;
}

static BOOL LC32SetValidationError(NSError **error, NSString *description) {
    if(error) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFileReadCorruptFileError
                                 userInfo:@{
            NSLocalizedDescriptionKey: description
        }];
    }
    return NO;
}

static BOOL LC32ValidateSignaturesPlist(NSDictionary *frameworks,
                                        NSError **error) {
    for(id frameworkName in frameworks) {
        if(!LC32IsSafePathComponent(frameworkName)) {
            return LC32SetValidationError(error,
                [NSString stringWithFormat:
                    @"Invalid framework path component: %@", frameworkName]);
        }

        id classes = frameworks[frameworkName];
        if(![classes isKindOfClass:NSDictionary.class]) {
            return LC32SetValidationError(error,
                [NSString stringWithFormat:
                    @"Framework %@ is not a dictionary", frameworkName]);
        }

        for(id className in classes) {
            if(!LC32IsSafePathComponent(className)) {
                return LC32SetValidationError(error,
                    [NSString stringWithFormat:
                        @"Invalid class path component: %@/%@",
                        frameworkName, className]);
            }

            id methodKinds = classes[className];
            if(![methodKinds isKindOfClass:NSDictionary.class]) {
                return LC32SetValidationError(error,
                    [NSString stringWithFormat:
                        @"Class %@/%@ is not a dictionary",
                        frameworkName, className]);
            }

            for(id kind in methodKinds) {
                if(![kind isKindOfClass:NSString.class] ||
                   (![(NSString *)kind isEqualToString:@"+"] &&
                    ![(NSString *)kind isEqualToString:@"-"])) {
                    return LC32SetValidationError(error,
                        [NSString stringWithFormat:
                            @"Invalid method kind for %@/%@: %@",
                            frameworkName, className, kind]);
                }

                id methods = methodKinds[kind];
                if(![methods isKindOfClass:NSDictionary.class]) {
                    return LC32SetValidationError(error,
                        [NSString stringWithFormat:
                            @"Method kind %@ for %@/%@ is not a dictionary",
                            kind, frameworkName, className]);
                }

                for(id selectorName in methods) {
                    id typeEncoding = methods[selectorName];
                    if(![selectorName isKindOfClass:NSString.class] ||
                       [(NSString *)selectorName length] == 0 ||
                       ![typeEncoding isKindOfClass:NSString.class] ||
                       [(NSString *)typeEncoding length] == 0) {
                        return LC32SetValidationError(error,
                            [NSString stringWithFormat:
                                @"Invalid method entry for %@/%@: %@",
                                frameworkName, className, selectorName]);
                    }
                }
            }
        }
    }
    return YES;
}

static BOOL LC32ValidateFrameworkMap(NSDictionary *frameworkMap,
                                     NSDictionary *frameworks,
                                     NSError **error) {
    for(id sourceKey in frameworkMap) {
        id destinationFramework = frameworkMap[sourceKey];
        if(![sourceKey isKindOfClass:NSString.class] ||
           ![destinationFramework isKindOfClass:NSString.class]) {
            return LC32SetValidationError(error,
                @"Framework map keys and values must be strings");
        }

        NSArray<NSString *> *sourceComponents =
            [(NSString *)sourceKey componentsSeparatedByString:@"/"];
        if(sourceComponents.count != 2 ||
           !LC32IsSafePathComponent(sourceComponents[0]) ||
           !LC32IsSafePathComponent(sourceComponents[1])) {
            return LC32SetValidationError(error,
                [NSString stringWithFormat:
                    @"Invalid framework map source: %@", sourceKey]);
        }

        NSString *sourceFramework = sourceComponents[0];
        NSString *sourceClass = sourceComponents[1];
        NSDictionary *classes = frameworks[sourceFramework];
        if(![classes isKindOfClass:NSDictionary.class] ||
           !classes[sourceClass]) {
            return LC32SetValidationError(error,
                [NSString stringWithFormat:
                    @"Framework map source is not in the signatures plist: %@",
                    sourceKey]);
        }

        if(![(NSString *)destinationFramework isEqualToString:@"-"] &&
           !LC32IsSafePathComponent(destinationFramework)) {
            return LC32SetValidationError(error,
                [NSString stringWithFormat:
                    @"Invalid destination framework for %@: %@",
                    sourceKey, destinationFramework]);
        }
    }

    // Resolve every class before creating the output directory so a routing
    // collision fails without leaving a partially generated source tree.
    NSMutableDictionary<NSString *, NSString *> *outputOwners =
        [NSMutableDictionary new];
    for(NSString *sourceFramework in frameworks) {
        NSDictionary *classes = frameworks[sourceFramework];
        for(NSString *sourceClass in classes) {
            NSString *sourceKey = [NSString stringWithFormat:@"%@/%@",
                                                              sourceFramework,
                                                              sourceClass];
            NSString *destinationFramework = frameworkMap[sourceKey];
            if([destinationFramework isEqualToString:@"-"]) continue;
            if(!destinationFramework) destinationFramework = sourceFramework;

            NSString *outputKey = [NSString stringWithFormat:@"%@/%@",
                                                              destinationFramework,
                                                              sourceClass];
            NSString *existingOwner = outputOwners[outputKey];
            if(existingOwner) {
                return LC32SetValidationError(error,
                    [NSString stringWithFormat:
                        @"Framework map collision at %@ between %@ and %@",
                        outputKey, existingOwner, sourceKey]);
            }
            outputOwners[outputKey] = sourceKey;
        }
    }
    return YES;
}

static BOOL LC32WriteClass(ClassBuilder *classBuilder,
                           NSString *outputPath,
                           NSError **error) {
    NSString *fileName =
        [classBuilder.className stringByAppendingPathExtension:@"m"];
    NSString *filePath = [outputPath stringByAppendingPathComponent:fileName];
    return [classBuilder.description writeToFile:filePath
                                      atomically:YES
                                        encoding:NSUTF8StringEncoding
                                           error:error];
}

typedef struct {
    NSUInteger generated;
    NSUInteger unavailable;
    NSUInteger failures;
} LC32RuntimeGenerationResult;

static LC32RuntimeGenerationResult
LC32GenerateRuntimeUIKitExtras(NSString *outputRoot) {
    LC32RuntimeGenerationResult result = {0};
    NSString *uikitPath = @"/System/Library/Frameworks/UIKit.framework/UIKit";
    NSArray<NSString *> *classes = @[
        @"UIDynamicSystemColor", @"UIDynamicColor", @"UILayoutContainerView",
        @"UICachedDeviceWhiteColor", @"UIDeviceWhiteColor", @"UIDeviceRGBColor",
        @"UITableViewCellLayoutManager", @"_UIMoreListTableView",
        @"UIMoreListCellLayoutManager", @"UIMoreListController",
        @"UIMoreNavigationController", @"UINibDecoder"
    ];
    NSString *outputPath =
        [outputRoot stringByAppendingPathComponent:@"UIKit"];
    NSError *error = nil;
    if(![NSFileManager.defaultManager
            createDirectoryAtPath:outputPath
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&error]) {
        fprintf(stderr, "Could not create %s: %s\n",
                outputPath.UTF8String, error.localizedDescription.UTF8String);
        result.failures++;
        return result;
    }

    for(NSString *className in classes) {
        NSString *fileName =
            [className stringByAppendingPathExtension:@"m"];
        NSString *filePath =
            [outputPath stringByAppendingPathComponent:fileName];
        if([NSFileManager.defaultManager fileExistsAtPath:filePath]) {
            fprintf(stderr,
                    "Keeping captured UIKit class instead of runtime class: %s\n",
                    className.UTF8String);
            continue;
        }

        Class cls = NSClassFromString(className);
        if(!cls) {
            fprintf(stderr, "Runtime UIKit class not found: %s\n",
                    className.UTF8String);
            result.unavailable++;
            continue;
        }

        ClassBuilder *classBuilder =
            [[ClassBuilder alloc] initWithClass:cls imagePath:uikitPath];
        error = nil;
        if(!LC32WriteClass(classBuilder, outputPath, &error)) {
            fprintf(stderr, "Could not write runtime class %s: %s\n",
                    className.UTF8String,
                    error.localizedDescription.UTF8String);
            result.failures++;
            continue;
        }
        result.generated++;
    }
    return result;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL includeRuntimeUIKit = NO;
        NSString *frameworkMapPath = nil;
        BOOL invalidArguments = argc < 3;
        for(int argumentIndex = 3;
            !invalidArguments && argumentIndex < argc;
            argumentIndex++) {
            if(strcmp(argv[argumentIndex], "--runtime-uikit") == 0) {
                if(includeRuntimeUIKit) {
                    invalidArguments = YES;
                } else {
                    includeRuntimeUIKit = YES;
                }
            } else if(strcmp(argv[argumentIndex], "--framework-map") == 0) {
                if(frameworkMapPath || argumentIndex + 1 >= argc) {
                    invalidArguments = YES;
                } else {
                    frameworkMapPath =
                        [@(argv[++argumentIndex]) stringByStandardizingPath];
                }
            } else {
                invalidArguments = YES;
            }
        }
        if(invalidArguments) {
            fprintf(stderr,
                    "Usage: %s INPUT_PLIST EMPTY_OUTPUT_DIRECTORY "
                    "[--framework-map PATH] [--runtime-uikit]\n",
                    argv[0]);
            return 2;
        }

        NSString *inputPath = [@(argv[1]) stringByStandardizingPath];
        NSString *outputRoot = [@(argv[2]) stringByStandardizingPath];
        NSDictionary *frameworks =
            [NSDictionary dictionaryWithContentsOfFile:inputPath];
        if(![frameworks isKindOfClass:NSDictionary.class]) {
            fprintf(stderr, "Could not read signatures plist: %s\n",
                    inputPath.UTF8String);
            return 1;
        }

        NSError *error = nil;
        if(!LC32ValidateSignaturesPlist(frameworks, &error)) {
            fprintf(stderr, "Invalid signatures plist %s: %s\n",
                    inputPath.UTF8String,
                    error.localizedDescription.UTF8String);
            return 1;
        }

        NSDictionary *frameworkMap = @{};
        if(frameworkMapPath) {
            frameworkMap =
                [NSDictionary dictionaryWithContentsOfFile:frameworkMapPath];
            if(![frameworkMap isKindOfClass:NSDictionary.class]) {
                fprintf(stderr, "Could not read framework map plist: %s\n",
                        frameworkMapPath.UTF8String);
                return 1;
            }
        }
        if(!LC32ValidateFrameworkMap(frameworkMap, frameworks, &error)) {
            fprintf(stderr, "Invalid framework map%s%s: %s\n",
                    frameworkMapPath ? " " : "",
                    frameworkMapPath ? frameworkMapPath.UTF8String : "",
                    error.localizedDescription.UTF8String);
            return 1;
        }

        if(!LC32CreateEmptyOutputDirectory(outputRoot, &error)) {
            fprintf(stderr, "Could not use output directory %s: %s\n",
                    outputRoot.UTF8String,
                    error.localizedDescription.UTF8String);
            return 1;
        }

        NSUInteger frameworkCount = 0;
        NSUInteger classCount = 0;
        NSUInteger methodCount = 0;
        NSUInteger skippedIncompleteMethods = 0;
        NSUInteger skippedFilteredMethods = 0;
        NSUInteger writeFailureCount = 0;
        NSMutableSet<NSString *> *createdFrameworks = [NSMutableSet new];

        NSArray<NSString *> *frameworkNames =
            [frameworks.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for(NSString *frameworkName in frameworkNames) {
            NSDictionary *classes = frameworks[frameworkName];
            if(![classes isKindOfClass:NSDictionary.class]) {
                fprintf(stderr, "Invalid framework entry: %s\n",
                        frameworkName.UTF8String);
                writeFailureCount++;
                continue;
            }

            NSArray<NSString *> *classNames =
                [classes.allKeys sortedArrayUsingSelector:@selector(compare:)];
            for(NSString *className in classNames) {
                @autoreleasepool {
                    NSString *sourceKey =
                        [NSString stringWithFormat:@"%@/%@",
                                                   frameworkName, className];
                    NSString *destinationFramework = frameworkMap[sourceKey];
                    if([destinationFramework isEqualToString:@"-"]) continue;
                    if(!destinationFramework) {
                        destinationFramework = frameworkName;
                    }

                    NSString *outputPath = [outputRoot
                        stringByAppendingPathComponent:destinationFramework];
                    if(![createdFrameworks
                            containsObject:destinationFramework]) {
                        error = nil;
                        if(![NSFileManager.defaultManager
                                createDirectoryAtPath:outputPath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error]) {
                            fprintf(stderr,
                                    "Could not create framework directory "
                                    "%s: %s\n",
                                    outputPath.UTF8String,
                                    error.localizedDescription.UTF8String);
                            writeFailureCount++;
                            continue;
                        }
                        [createdFrameworks addObject:destinationFramework];
                        frameworkCount++;
                    }

                    NSDictionary *methodSignatures = classes[className];
                    if(![methodSignatures isKindOfClass:NSDictionary.class]) {
                        fprintf(stderr, "Invalid class entry: %s/%s\n",
                                frameworkName.UTF8String,
                                className.UTF8String);
                        writeFailureCount++;
                        continue;
                    }

                    ClassBuilder *classBuilder = [[ClassBuilder alloc]
                        initWithClassName:className
                               imagePath:frameworkName
                        methodSignatures:methodSignatures];
                    methodCount += classBuilder.methods.count;
                    skippedIncompleteMethods +=
                        classBuilder.skippedIncompleteMethods;
                    skippedFilteredMethods +=
                        classBuilder.skippedFilteredMethods;

                    error = nil;
                    if(!LC32WriteClass(classBuilder, outputPath, &error)) {
                        fprintf(stderr,
                                "Could not write %s/%s to %s: %s\n",
                                frameworkName.UTF8String,
                                className.UTF8String,
                                destinationFramework.UTF8String,
                                error.localizedDescription.UTF8String);
                        writeFailureCount++;
                        continue;
                    }
                    classCount++;
                }
            }
        }

        LC32RuntimeGenerationResult runtimeResult = {0};
        if(includeRuntimeUIKit) {
            runtimeResult = LC32GenerateRuntimeUIKitExtras(outputRoot);
        }
        printf("Generated %lu methods in %lu classes from %lu frameworks; "
               "skipped %lu incomplete and %lu filtered methods",
               (unsigned long)methodCount,
               (unsigned long)classCount,
               (unsigned long)frameworkCount,
               (unsigned long)skippedIncompleteMethods,
               (unsigned long)skippedFilteredMethods);
        if(includeRuntimeUIKit) {
            printf("; added %lu runtime UIKit classes, %lu unavailable",
                   (unsigned long)runtimeResult.generated,
                   (unsigned long)runtimeResult.unavailable);
        }
        printf(".\n");

        return writeFailureCount == 0 && runtimeResult.failures == 0 &&
               runtimeResult.unavailable == 0 ? 0 : 1;
    }
}
