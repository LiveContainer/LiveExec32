#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CLLocation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>

// Model the guest's float-based public structs while compiling the real
// conversion helpers on a 64-bit host. Coordinates stay double on both ABIs.
typedef struct { float dx, dy; } LC32TestVector;
typedef struct { float horizontal, vertical; } LC32TestOffset;
typedef struct { float x, y; } LC32TestPoint;
typedef struct { float width, height; } LC32TestSize;
typedef struct { LC32TestPoint origin; LC32TestSize size; } LC32TestRect;
typedef struct { float top, left, bottom, right; } LC32TestInsets;
typedef struct { float a, b, c, d, tx, ty; } LC32TestTransform;
#define CGVector LC32TestVector
#define UIOffset LC32TestOffset
#define CGPoint LC32TestPoint
#define CGSize LC32TestSize
#define CGRect LC32TestRect
#define UIEdgeInsets LC32TestInsets
#define CGAffineTransform LC32TestTransform
#import <CoreGraphics/CoreGraphics+LC32.h>
#import <UIKit/UIKit+LC32.h>

_Static_assert(sizeof(CGVector) == 8, "guest vector layout");
_Static_assert(sizeof(UIOffset) == 8, "guest offset layout");
_Static_assert(sizeof(CLLocationCoordinate2D) == 16, "coordinate layout");
_Static_assert(sizeof(LC32Floats2_64) == 16, "host pair layout");
_Static_assert(sizeof(LC32Floats4_64) == 32, "host four-float layout");
_Static_assert(sizeof(LC32Floats6_64) == 48, "host transform layout");

static unsigned failures, hostCalls;
static const CGVector vector = {1.25f, -2.5f};
static const UIOffset offset = {-3.75f, 4.5f};
static const CLLocationCoordinate2D coordinate = {10.1234567890123, -106.987654321098};
static const CGPoint point = {1.25f, -2.5f};
static const CGSize size = {3.75f, 4.5f};
static const CGRect rect = {{1.25f, -2.5f}, {3.75f, 4.5f}};
static const UIEdgeInsets insets = {1.25f, -2.5f, 3.75f, 4.5f};
static const CGAffineTransform transform = {1.25f, -2.5f, 3.75f, 4.5f, -5.25f, 6.5f};
static const double nativeResult[] = {1.123456789, -2.987654321,
    3.123456789, -4.987654321, 5.123456789, -6.987654321};
static void check(BOOL pass, const char *message) {
    if(!pass) { fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
static BOOL LC32ObjCTraceEnabled(void) { return NO; }
@interface NSObject (LC32TestHostSelf)
- (uint64_t)host_self;
@end
@implementation NSObject (LC32TestHostSelf)
- (uint64_t)host_self { return (uintptr_t)self; }
@end

@interface LC32SimpleStructFixture : NSObject
- (CGVector)vector;
- (void)setVector:(CGVector)value;
- (UIOffset)offset;
- (void)setOffset:(UIOffset)value;
- (CLLocationCoordinate2D)coordinate;
- (void)setCoordinate:(CLLocationCoordinate2D)value;
- (CLLocationCoordinate2D)coordinateWithVector:(CGVector)v offset:(UIOffset)o scale:(float)s;
- (CGPoint)point;
- (void)setPoint:(CGPoint)value;
- (CGSize)size;
- (void)setSize:(CGSize)value;
- (CGRect)rect;
- (void)setRect:(CGRect)value;
- (UIEdgeInsets)insets;
- (void)setInsets:(UIEdgeInsets)value;
- (CGAffineTransform)transform;
- (void)setTransform:(CGAffineTransform)value;
@end
@interface LC32UnsupportedStructFixture : NSObject
@end

static const uint64_t aggregateTag = UINT64_C(0xabcd000000000000);
static uint64_t LC32HostAggregateArgument(const void *storage) {
    check(((uintptr_t)storage & aggregateTag) == 0, "test pointer overlaps tag");
    return aggregateTag | (uintptr_t)storage;
}
static const void *aggregate(va_list *arguments) {
    uint64_t value = va_arg(*arguments, uint64_t);
    check((value & aggregateTag) == aggregateTag, "missing aggregate descriptor");
    return (const void *)(uintptr_t)(value & ~aggregateTag);
}
static void checkVector(const LC32Floats2_64 *value) {
    check(value->values[0] == vector.dx && value->values[1] == vector.dy, "vector widening");
}
static void checkOffset(const LC32Floats2_64 *value) {
    check(value->values[0] == offset.horizontal && value->values[1] == offset.vertical, "offset widening");
}
static void checkWidened(const void *host, const void *guest, size_t count) {
    for(size_t i = 0; i < count; ++i) {
        float g;
        double h;
        memcpy(&g, (const char *)guest + i * sizeof(g), sizeof(g));
        memcpy(&h, (const char *)host + i * sizeof(h), sizeof(h));
        check(h == (double)g, "float aggregate widening");
    }
}
static void checkNarrowed(const void *guest, size_t count) {
    for(size_t i = 0; i < count; ++i) {
        float value;
        memcpy(&value, (const char *)guest + i * sizeof(value), sizeof(value));
        check(value == (float)nativeResult[i], "float aggregate narrowing");
    }
}
static uint64_t LC32CachedHostSelector(uint64_t *cache, SEL selector, BOOL returnsStruct) {
    const char *name = sel_getName(selector);
    check(returnsStruct == (strncmp(name, "set", 3) != 0), "structure-return flag");
    if(!*cache) memcpy(cache, &selector, sizeof(selector));
    return *cache;
}
static uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t command, ...) {
    check(object != 0, "missing receiver");
    ++hostCalls;
    SEL selector = (SEL)(uintptr_t)command;
    const char *name = sel_getName(selector);
    BOOL returnsStruct = strncmp(name, "set", 3) != 0;
    va_list arguments;
    va_start(arguments, command);
    void *result = NULL;
    if(returnsStruct) {
        result = va_arg(arguments, void *);
        size_t expected = sel_isEqual(selector, @selector(transform)) ? 48 :
            (sel_isEqual(selector, @selector(rect)) ||
             sel_isEqual(selector, @selector(insets))) ? 32 : 16;
        check(va_arg(arguments, size_t) == expected, "native result storage size");
    }
    if(sel_isEqual(selector, @selector(setVector:))) {
        checkVector(aggregate(&arguments));
    } else if(sel_isEqual(selector, @selector(setOffset:))) {
        checkOffset(aggregate(&arguments));
    } else if(sel_isEqual(selector, @selector(setCoordinate:))) {
        check(!memcmp(aggregate(&arguments), &coordinate, sizeof(coordinate)), "coordinate precision");
    } else if(sel_isEqual(selector, @selector(vector))) {
        // Deliberately use more precision than float to test result narrowing.
        *(LC32Floats2_64 *)result = (LC32Floats2_64){{1.123456789, -2.987654321}};
    } else if(sel_isEqual(selector, @selector(offset))) {
        *(LC32Floats2_64 *)result = (LC32Floats2_64){{-3.123456789, 4.987654321}};
    } else if(sel_isEqual(selector, @selector(coordinate))) {
        memcpy(result, &coordinate, sizeof(coordinate));
    } else if(sel_isEqual(selector, @selector(coordinateWithVector:offset:scale:))) {
        checkVector(aggregate(&arguments));
        checkOffset(aggregate(&arguments));
        check(va_arg(arguments, double) == 0.5, "mixed floating scalar");
        memcpy(result, &coordinate, sizeof(coordinate));
    } else if(sel_isEqual(selector, @selector(setPoint:))) {
        checkWidened(aggregate(&arguments), &point, 2);
    } else if(sel_isEqual(selector, @selector(setSize:))) {
        checkWidened(aggregate(&arguments), &size, 2);
    } else if(sel_isEqual(selector, @selector(setRect:))) {
        checkWidened(aggregate(&arguments), &rect, 4);
    } else if(sel_isEqual(selector, @selector(setInsets:))) {
        checkWidened(aggregate(&arguments), &insets, 4);
    } else if(sel_isEqual(selector, @selector(setTransform:))) {
        checkWidened(aggregate(&arguments), &transform, 6);
    } else if(sel_isEqual(selector, @selector(point)) ||
              sel_isEqual(selector, @selector(size))) {
        memcpy(result, nativeResult, 16);
    } else if(sel_isEqual(selector, @selector(rect)) ||
              sel_isEqual(selector, @selector(insets))) {
        memcpy(result, nativeResult, 32);
    } else if(sel_isEqual(selector, @selector(transform))) {
        memcpy(result, nativeResult, 48);
    } else {
        check(NO, "unexpected host selector");
    }
    check(va_arg(arguments, uint64_t) == 0, "bridge terminator");
    va_end(arguments);
    return 0;
}

#include "LC32SimpleStructFixture.inc"
#include "LC32UnsupportedStructFixture.inc"

int main(void) {
    @autoreleasepool {
        LC32SimpleStructFixture *fixture = [LC32SimpleStructFixture new];
        // Exercise cold and warm selector caches.
        for(unsigned i = 0; i < 2; i++) {
            [fixture setVector:vector];
            [fixture setOffset:offset];
            [fixture setCoordinate:coordinate];
            CGVector v = [fixture vector];
            check(v.dx == (float)1.123456789 && v.dy == (float)-2.987654321, "vector narrowing");
            UIOffset o = [fixture offset];
            check(o.horizontal == (float)-3.123456789 && o.vertical == (float)4.987654321, "offset narrowing");
            CLLocationCoordinate2D c = [fixture coordinate];
            check(!memcmp(&c, &coordinate, sizeof(c)), "coordinate result precision");
            c = [fixture coordinateWithVector:vector offset:offset scale:0.5f];
            check(!memcmp(&c, &coordinate, sizeof(c)), "mixed aggregate result");
            [fixture setPoint:point];
            [fixture setSize:size];
            [fixture setRect:rect];
            [fixture setInsets:insets];
            [fixture setTransform:transform];
            CGPoint p = [fixture point]; checkNarrowed(&p, 2);
            CGSize s = [fixture size]; checkNarrowed(&s, 2);
            CGRect r = [fixture rect]; checkNarrowed(&r, 4);
            UIEdgeInsets e = [fixture insets]; checkNarrowed(&e, 4);
            CGAffineTransform t = [fixture transform]; checkNarrowed(&t, 6);
        }
        check(hostCalls == 34, "host call count");
        check(![LC32UnsupportedStructFixture instancesRespondToSelector:@selector(setCoordinatePointer:)],
            "unsupported pointer method was enabled");
        printf("generated simple structs (host recorder): %s\n", failures ? "FAIL" : "PASS");
    }
    return failures != 0;
}
