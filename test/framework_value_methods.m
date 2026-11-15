#import <SceneKit/SceneKit.h>
#import <MapKit/MapKit.h>
#import <LC32/LC32.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static unsigned failures;
static void check(BOOL pass, const char *name) {
    printf("framework-value-%s: %s\n", name, pass ? "PASS" : "FAIL");
    failures += !pass;
}

static void checkBox(NSValue *value, const void *expected, size_t size, const char *encoding) {
    check(value && !strcmp(value.objCType, encoding), "encoding");
    uint8_t bytes[80];
    memset(bytes, 0xa5, sizeof(bytes));
    [value getValue:bytes + 8];
    check(!memcmp(bytes + 8, expected, size), "guest-getValue");
    BOOL guards = YES;
    for(unsigned i = 0; i < 8; ++i) guards &= bytes[i] == 0xa5;
    for(unsigned i = (unsigned)size + 8; i < sizeof(bytes); ++i) guards &= bytes[i] == 0xa5;
    check(guards, "guest-write-width");
    memset(bytes, 0xa5, sizeof(bytes));
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(&descriptor, bytes + 8, size);
    LC32InvokeHostSelector(value.host_self, LC32GetHostSelector(@selector(getValue:)),
        LC32HostSizedIndirectArgument(&descriptor), (uint64_t)0);
    check(!memcmp(bytes + 8, expected, size), "native-layout");
}

static NSValue *nativeBox(const void *bytes, size_t size, const char *encoding) {
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(&descriptor, (void *)bytes, size);
    const uint64_t type = LC32GuestToHostCString(encoding, 0);
    NSValue *value = LC32InvokeHostObjectSelector([(id)NSValue.class host_self],
        LC32GetHostSelector(@selector(valueWithBytes:objCType:)),
        LC32HostSizedIndirectArgument(&descriptor), type, (uint64_t)0);
    LC32GuestToHostCStringFree(type);
    return LC32ReturnBorrowedGuestObject(value);
}

int main(void) {
    @autoreleasepool {
        CGPoint point = [NSValue valueWithCGPoint:CGPointMake(1.25, -2.5)].CGPointValue;
        check(point.x == 1.25 && point.y == -2.5, "point-roundtrip");
        CGSize size = [NSValue valueWithCGSize:CGSizeMake(3.75, 4.5)].CGSizeValue;
        check(size.width == 3.75 && size.height == 4.5, "size-roundtrip");
        CGRect rect = [NSValue valueWithCGRect:CGRectMake(1.25, -2.5, 3.75, 4.5)].CGRectValue;
        check(rect.origin.x == 1.25 && rect.origin.y == -2.5 &&
            rect.size.width == 3.75 && rect.size.height == 4.5, "rect-roundtrip");
        UIEdgeInsets insets = [NSValue valueWithUIEdgeInsets:
            UIEdgeInsetsMake(1.25, -2.5, 3.75, 4.5)].UIEdgeInsetsValue;
        check(insets.top == 1.25 && insets.left == -2.5 &&
            insets.bottom == 3.75 && insets.right == 4.5, "insets-roundtrip");
        CGAffineTransform transform = {1.25, -2.5, 3.75, 4.5, -5.25, 6.5};
        transform = [NSValue valueWithCGAffineTransform:transform].CGAffineTransformValue;
        check(transform.a == 1.25 && transform.b == -2.5 && transform.c == 3.75 &&
            transform.d == 4.5 && transform.tx == -5.25 && transform.ty == 6.5,
            "transform-roundtrip");
        CGVector vector = [NSValue valueWithCGVector:CGVectorMake(1.25, -2.5)].CGVectorValue;
        check(vector.dx == 1.25 && vector.dy == -2.5, "cgvector-roundtrip");
        UIOffset offset = [NSValue valueWithUIOffset:UIOffsetMake(3.5, -4.25)].UIOffsetValue;
        check(offset.horizontal == 3.5 && offset.vertical == -4.25, "uioffset-roundtrip");
        CLLocationCoordinate2D coordinate = [NSValue valueWithMKCoordinate:
            CLLocationCoordinate2DMake(12.25, -31.5)].MKCoordinateValue;
        check(coordinate.latitude == 12.25 && coordinate.longitude == -31.5, "coordinate-roundtrip");
        SCNVector3 vector3 = SCNVector3Make(1.25, -2.5, 3.75);
        NSValue *value = [NSValue valueWithSCNVector3:vector3];
        checkBox(value, &vector3, sizeof(vector3), @encode(SCNVector3));
        check(SCNVector3EqualToVector3(value.SCNVector3Value, vector3), "vector3-roundtrip");
        vector3.z = 7.25;
        value = nativeBox(&vector3, sizeof(vector3), @encode(SCNVector3));
        checkBox(value, &vector3, sizeof(vector3), @encode(SCNVector3));
        check(SCNVector3EqualToVector3(value.SCNVector3Value, vector3), "vector3-native-box");

        SCNVector4 vector4 = SCNVector4Make(1.25, -2.5, 3.75, -4.125);
        value = [NSValue valueWithSCNVector4:vector4];
        checkBox(value, &vector4, sizeof(vector4), @encode(SCNVector4));
        check(SCNVector4EqualToVector4(value.SCNVector4Value, vector4), "vector4-roundtrip");
        vector4.w = 9.5;
        value = nativeBox(&vector4, sizeof(vector4), @encode(SCNVector4));
        check(SCNVector4EqualToVector4(value.SCNVector4Value, vector4), "vector4-native-box");

        SCNMatrix4 matrix = {1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14, 15, -16};
        value = [NSValue valueWithSCNMatrix4:matrix];
        checkBox(value, &matrix, sizeof(matrix), @encode(SCNMatrix4));
        check(SCNMatrix4EqualToMatrix4(value.SCNMatrix4Value, matrix), "matrix-roundtrip");
        matrix.m42 = 12.5;
        value = nativeBox(&matrix, sizeof(matrix), @encode(SCNMatrix4));
        checkBox(value, &matrix, sizeof(matrix), @encode(SCNMatrix4));
        check(SCNMatrix4EqualToMatrix4(value.SCNMatrix4Value, matrix), "matrix-native-box");

        MKCoordinateSpan span = MKCoordinateSpanMake(1.25, 2.5);
        value = [NSValue valueWithMKCoordinateSpan:span];
        checkBox(value, &span, sizeof(span), @encode(MKCoordinateSpan));
        check(value.MKCoordinateSpanValue.latitudeDelta == 1.25 &&
            value.MKCoordinateSpanValue.longitudeDelta == 2.5, "span-roundtrip");
        span.latitudeDelta = 7.5;
        value = nativeBox(&span, sizeof(span), @encode(MKCoordinateSpan));
        checkBox(value, &span, sizeof(span), @encode(MKCoordinateSpan));
        check(value.MKCoordinateSpanValue.latitudeDelta == 7.5 &&
            value.MKCoordinateSpanValue.longitudeDelta == 2.5, "span-native-box");
    }
    return failures != 0;
}
