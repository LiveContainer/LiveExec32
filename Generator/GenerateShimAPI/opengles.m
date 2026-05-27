@import UIKit;

@interface MethodParameter : NSObject
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *type;
@property(nonatomic) int index;
@end
@implementation MethodParameter
+ (BOOL)isDirectCastType:(NSString *)type {
    // GLclampf, GLfloat
    return [@[
        @"GLbitfield", @"GLboolean", @"GLbyte",
        @"GLenum", @"GLint", @"GLshort", @"GLsizei",
        @"GLubyte", @"GLuint", @"GLushort", @"GLchar",
        @"GLclampx", @"GLfixed", @"GLhalf", @"GLint64", @"GLuint64"
    ] containsObject:type];
}

- (instancetype)initWithIndex:(int)index name:(NSString *)name type:(NSString *)type {
    self = [super init];
    self.index = index;
    self.type = [type stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    self.name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];;
    return self;
}

- (NSString *)declarationInMethod {
    return [NSString stringWithFormat:@"%@ %@", self.type, self.name];
}

- (NSString *)declaration {
    if([MethodParameter isDirectCastType:self.type]) {
        return [NSString stringWithFormat:@"uint64_t host_arg%1$d = (uint64_t)guest_arg%1$d;", self.index];
    }
    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
}

- (NSString *)parameterToBePassed {
    if([MethodParameter isDirectCastType:self.type]) {
        return [NSString stringWithFormat:@"guest_arg%d", self.index];
    }
    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
}

- (NSString *)postCall {
    if([MethodParameter isDirectCastType:self.type]) {
        return [NSString stringWithFormat:@"// No post-process for guest_arg%d", self.index];
    }
    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.type];
}
@end

NSArray *splitTypeAndName(NSString *str) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"gl[a-zA-Z0-9]+" options:0 error:NULL];
    NSTextCheckingResult *newSearchString = [regex firstMatchInString:str options:0 range:NSMakeRange(0, str.length)];
    NSInteger splitIndex = newSearchString.range.location;
    return @[[[str substringToIndex:splitIndex] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], [str substringFromIndex:splitIndex]];
}

NSArray *splitBaseNameAndExtension(NSString *str) {
    NSError *error = nil;
    NSString *pattern = @"(\\w+)(APPLE|EXT|OES)";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if (error) {
        NSLog(@"Regex error: %@", error.localizedDescription);
        return nil;
    }

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:str options:0 range:NSMakeRange(0, str.length)];
    NSTextCheckingResult *match = matches.firstObject;
    if (match.numberOfRanges == 3) {
        NSString *name = [str substringWithRange:[match rangeAtIndex:1]];
        NSString *ext = [str substringWithRange:[match rangeAtIndex:2]];
        return @[name, ext];
    }
    return nil;
}

@interface MethodBuilder : NSObject
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *returnType;
@property(nonatomic, retain) NSString *argsStr;
@property(nonatomic, retain) NSMutableArray<MethodParameter *> *parameters;
@property(nonatomic, retain) NSMutableArray<NSString *> *lines;
@end
@implementation MethodBuilder
- (instancetype)initWithName:(NSString *)name returnType:(NSString *)returnType args:(NSString *)argsStr {
    self = [super init];
    self.lines = [NSMutableArray new];
    self.parameters = [NSMutableArray new];
    self.name = name;
    self.returnType = returnType;
    self.argsStr = argsStr;
    if(![argsStr isEqualToString:@"void"]) {
        NSError *error = nil;
        NSString *pattern = @"(\\w+(.*?)(\\s+|\\*))(\\w+)(?:,|\\z)";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
        if (error) {
            NSLog(@"Regex error: %@", error.localizedDescription);
            return nil;
        }

        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:argsStr options:0 range:NSMakeRange(0, argsStr.length)];
        for(int i = 0; i < matches.count; i++) {
            NSTextCheckingResult *match = matches[i];
            if (match.numberOfRanges == 5) {
                NSString *type = [argsStr substringWithRange:[match rangeAtIndex:1]];
                NSString *name = [argsStr substringWithRange:[match rangeAtIndex:4]];
                [self.parameters addObject:[[MethodParameter alloc] initWithIndex:i name:name type:type]];
            }
        }
    }

    // declare method
    //[self.lines addObject:[NSString stringWithFormat:@"// %@", self.method.description]];
    [self.lines addObject:[NSString stringWithFormat:@"%@ {", [self prettyNameForExtension:@""]]];

    // debug: log calls
    [self.lines addObject:@"  printf(\"DBG: call %s\\n\", __func__);"];

    // pull host function
    [self.lines addObject:[NSString stringWithFormat:@"  static uint64_t _host_cmd;"]];
    [self.lines addObject:[NSString stringWithFormat:@"  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);"]];

    // pull host objects
    NSMutableString *methodDeclaration = [NSMutableString new];
    for(MethodParameter *param in self.parameters) {
        [self.lines addObject:[NSString stringWithFormat:@"  %@ ", param.declaration]];
    }

    // invoke function
    [self.lines addObject:[NSString stringWithFormat:@"  %@", self.callLine]];

    // post-call: eg set NSError pointer
    for(MethodParameter *param in self.parameters) {
        [self.lines addObject:[NSString stringWithFormat:@"  %@ ", param.postCall]];
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

- (NSString *)prettyNameForExtension:(NSString *)extension {
    return [NSString stringWithFormat:@"%@ %@%@(%@)", self.returnType, self.name, extension, self.argsStr];
}

- (void)addExtension:(NSString *)extension {
    NSString *line = [NSString stringWithFormat:@"__asm__(\".global _%1$@%2$@\\n _%1$@%2$@ = _%1$@\");", self.name, extension];
    if(![self.lines containsObject:line]) {
        [self.lines addObject:line];
    }
/*
__asm__(" \n \
.section	__DATA,__objc_data \n \
.global ___CFConstantStringClassReference \n \
___CFConstantStringClassReference = _OBJC_CLASS_$___NSCFConstantString \
");
*/
}

- (NSString *)callLine {
    NSMutableString *call = [NSMutableString new];
    [call appendString:@"uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd"];
    for(MethodParameter *param in self.parameters) {
        [call appendFormat:@", %@", param.parameterToBePassed];
    }
    [call appendString:@");"];
    return call;
}

- (NSString *)returnLine {
    if([MethodParameter isDirectCastType:self.returnType]) {
        return [NSString stringWithFormat:@"return (%@)host_ret;", self.returnType];
    } else if([@[@"void", @"GLvoid"] containsObject:self.returnType]) {
        return @"// return void";
    }
    return [NSString stringWithFormat:@"/* %s: unhandled type %@ */", sel_getName(_cmd), self.returnType];
}

- (NSString *)description {
    return [self.lines componentsJoinedByString:@"\n"];
}
@end

int main() {
    chdir(NSBundle.mainBundle.bundlePath.UTF8String);
    NSString *template = [NSString stringWithContentsOfFile:@"../templates/opengles.txt"];
    NSMutableDictionary *map = [NSMutableDictionary new];
    for(NSString *_line in [template componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [_line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if(line.length < 2) continue;

        // Remove )
        NSArray *nameAndArgs = [[line substringToIndex:line.length-1] componentsSeparatedByString:@"("];
        NSArray *returnTypeAndName = splitTypeAndName(nameAndArgs[0]);
        NSString *returnType = returnTypeAndName[0];
        NSString *name = returnTypeAndName[1];
        NSString *argsStr = nameAndArgs[1];

        // Get base name and extension
        NSArray *nameAndExt = splitBaseNameAndExtension(name);
        if(nameAndExt) {
            name = nameAndExt[0];
        }

        MethodBuilder *method = map[name];
        if(!method) {
            method = [[MethodBuilder alloc] initWithName:name returnType:returnType args:argsStr];
            map[name] = method;
        }

        if(nameAndExt) {
            [method addExtension:nameAndExt[1]];
        }
    }

    printf("#import <OpenGLES/ES3/gl.h>\n");
    printf("#import <LC32/LC32.h>\n");
    for(NSString *name in map) {
        MethodBuilder *method = map[name];
        printf("%s\n", method.description.UTF8String);
    }
}
