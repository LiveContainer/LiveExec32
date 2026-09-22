#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../include/LC32PODType.h"

// Fixed-width fields keep these declarations identical in the native control
// and ARM32 runs. CGRect below intentionally follows each platform's CGFloat.
typedef struct { int8_t tag; double value; int16_t tail; } Padded;
typedef struct { float values[3]; } FloatArray;
typedef struct { uint64_t values[3]; } Large;
typedef struct { uint64_t high; float low; } Pair;
static unsigned checks, failures, calls;
static id expectedObject;
static BOOL captured;
static void check(const char *name, BOOL pass) {
    printf("forwarding-structs-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}

@protocol StructMessages
- (void)fetchAdForSpace:(id)space frame:(CGRect)frame size:(int)size;
- (double)padded:(Padded)value tail:(int)tail;
- (int)large:(Large)value array:(FloatArray)array tail:(int)tail;
- (double)floats:(CGRect)a b:(CGRect)b c:(CGRect)c tail:(double)tail;
- (int)integers:(int)a b:(int)b c:(int)c d:(int)d e:(int)e value:(Padded)value tail:(int)tail;
- (int)pair:(Pair)value tail:(int)tail;
- (int)split:(int)a b:(int)b c:(int)c d:(int)d e:(int)e value:(Pair)value tail:(int)tail;
- (int)narrow:(int8_t)a value:(Pair)value tail:(int16_t)tail;
@end

@interface StructTarget : NSObject
- (void)recordSpace:(id)space frame:(CGRect)frame size:(int)size;
@end
@implementation StructTarget
- (void)recordSpace:(id)space frame:(CGRect)frame size:(int)size {
    ++calls;
    captured = space == expectedObject && frame.origin.x == -3.5 &&
        frame.origin.y == 7.25 && frame.size.width == 320 &&
        frame.size.height == 50.5 && size == -17;
}
- (double)padded:(Padded)value tail:(int)tail {
    return value.tag + value.value + value.tail + tail;
}
- (int)large:(Large)value array:(FloatArray)array tail:(int)tail {
    return value.values[0] == UINT64_C(0x123456789abcdef0) &&
        value.values[1] == 19 && value.values[2] == UINT64_C(0xfedcba9876543210) &&
        array.values[0] == -1.5 && array.values[1] == 2.25 &&
        array.values[2] == 9.5 && tail == -31;
}
- (double)floats:(CGRect)a b:(CGRect)b c:(CGRect)c tail:(double)tail {
    return a.origin.x + b.origin.y + c.size.height + tail;
}
- (int)integers:(int)a b:(int)b c:(int)c d:(int)d e:(int)e value:(Padded)value tail:(int)tail {
    return a == 1 && b == 2 && c == 3 && d == 4 && e == 5 &&
        value.tag == -7 && value.value == 42.5 && value.tail == -300 && tail == 93;
}
- (int)pair:(Pair)value tail:(int)tail {
    return value.high == UINT64_C(0xfedcba9876543210) && value.low == -23.5 && tail == 93;
}
- (int)split:(int)a b:(int)b c:(int)c d:(int)d e:(int)e value:(Pair)value tail:(int)tail {
    return a == 1 && b == 2 && c == 3 && d == 4 && e == 5 && [self pair:value tail:tail];
}
- (int)narrow:(int8_t)a value:(Pair)value tail:(int16_t)tail {
    return a + (int)value.low + tail;
}
@end

@interface StructProxy : NSProxy {
    id _target;
}
- (id)initWithTarget:(id)target;
@end
@implementation StructProxy
- (id)initWithTarget:(id)target { _target = [target retain]; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if(selector == @selector(fetchAdForSpace:frame:size:)) selector = @selector(recordSpace:frame:size:);
    return [_target methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    if(invocation.selector == @selector(fetchAdForSpace:frame:size:)) {
        struct { uint32_t before; CGRect value; uint32_t after; } buffer;
        buffer.before = 0x12345678; buffer.after = 0x87654321;
        [invocation getArgument:&buffer.value atIndex:3];
        check("get-rectangle-canaries", buffer.before == 0x12345678 && buffer.after == 0x87654321);
        check("get-rectangle-fields", buffer.value.origin.x == -3.5 && buffer.value.size.height == 50.5);
        [invocation retainArguments];
        invocation.selector = @selector(recordSpace:frame:size:);
    }
    [invocation invokeWithTarget:_target];
}
- (void)dealloc { [_target release]; [super dealloc]; }
@end

int main(void) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        StructTarget *target = [StructTarget new];
        id<StructMessages> proxy = (id)[[StructProxy alloc] initWithTarget:target];
        expectedObject = [NSMutableString stringWithString:@"ad space"];
        CGRect rect = CGRectMake(-3.5, 7.25, 320, 50.5);
        [proxy fetchAdForSpace:expectedObject frame:rect size:-17];
        check("flurry-object-rectangle-integer", captured && calls == 1);
        Padded padded = {-7, 42.5, -300};
        check("padded-struct-double-return", [proxy padded:padded tail:9] == -255.5);
        Large large = {{UINT64_C(0x123456789abcdef0), 19, UINT64_C(0xfedcba9876543210)}};
        FloatArray array = {{-1.5, 2.25, 9.5}};
        check("indirect-struct-and-array", [proxy large:large array:array tail:-31]);
        check("floating-register-exhaustion", [proxy floats:rect b:rect c:rect tail:11.5] == 65.75);
        check("integer-register-exhaustion", [proxy integers:1 b:2 c:3 d:4 e:5 value:padded tail:93]);
        Pair pair = {UINT64_C(0xfedcba9876543210), -23.5};
        check("mixed-struct-in-registers", [proxy pair:pair tail:93]);
        check("mixed-struct-not-split-on-host", [proxy split:1 b:2 c:3 d:4 e:5 value:pair tail:93]);
        check("standalone-narrow-sign-extension", [proxy narrow:-7 value:pair tail:-300] == -330);
        // Values use the encoding's field types, but layout/padding is local.
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
            [target methodSignatureForSelector:@selector(padded:tail:)]];
        [invocation setArgument:&padded atIndex:2];
        struct { uint32_t before; Padded value; uint32_t after; } copy;
        memset(&copy, 0xa5, sizeof(copy));
        [invocation getArgument:&copy.value atIndex:2];
        check("padded-struct-canaries", copy.before == 0xa5a5a5a5 && copy.after == 0xa5a5a5a5);
        check("padded-struct-fields", copy.value.tag == -7 && copy.value.value == 42.5 && copy.value.tail == -300);
        char types[256];
        snprintf(types, sizeof(types), "%s@:", @encode(Padded));
        invocation = [NSInvocation invocationWithMethodSignature:
            [NSMethodSignature signatureWithObjCTypes:types]];
        [invocation setReturnValue:&padded];
        memset(&copy, 0xa5, sizeof(copy));
        [invocation getReturnValue:&copy.value];
        check("struct-return-storage-canaries", copy.before == 0xa5a5a5a5 && copy.after == 0xa5a5a5a5);
        check("struct-return-storage-fields", copy.value.tag == -7 && copy.value.value == 42.5 && copy.value.tail == -300);
        LC32PODType guestLayout, hostLayout;
        check("parser-padded-layout", LC32PODStructType("{Padded=cds}", 0, &guestLayout) &&
            LC32PODStructType("{Padded=cds}", 1, &hostLayout) &&
            guestLayout.size == 16 && hostLayout.size == 24 &&
            guestLayout.fields[1].offset == 4 && hostLayout.fields[1].offset == 8);
        check("parser-quoted-nested-array", LC32PODStructType("{Outer=\"nested\"{Inner=\"values\"[3f]}}", 1, &hostLayout) &&
            hostLayout.size == 12 && LC32PODHomogeneousFloat(&hostLayout) == 'f');
        const char *unsupported[] = {"{Opaque}", "{Empty=}", "{Pointer=^i}", "{Object=@}",
            "{Union=(U=if)}", "{Bits=b3}", "{Array=[33f]}", "{Array=[0f]}",
            "{Unclosed=ff", "{Trailing=ff}i", "{Bad=\"unterminated}", "{Bad=[3f}"};
        BOOL rejected = YES;
        for(unsigned i = 0; i < sizeof(unsupported) / sizeof(*unsupported); ++i)
            rejected &= !LC32PODStructType(unsupported[i], 1, &hostLayout);
        check("parser-rejects-unsafe-aggregates", rejected);
        [(id)proxy release]; [target release];
    }
    printf("forwarding-structs: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
