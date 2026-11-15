#import <MapKit/MapKit.h>
#import <LC32/LC32.h>
#include <math.h>
#include <stdio.h>

static unsigned failures;
static void check(BOOL passed, const char *name) {
    printf("mapkit-method-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

int main(void) {
    @autoreleasepool {
        // Must work before constructing any MK class or explicitly loading it.
        const CLLocationCoordinate2D expected = CLLocationCoordinate2DMake(12.25, -31.5);
        NSValue *value = [NSValue valueWithMKCoordinate:expected];
        const CLLocationCoordinate2D actual = value.MKCoordinateValue;
        check(value && actual.latitude == expected.latitude &&
            actual.longitude == expected.longitude, "native-category-loaded");
        MKMapView *view = [[MKMapView alloc] initWithFrame:CGRectMake(0, 0, 320, 240)];
        MKCoordinateRegion region = MKCoordinateRegionMake(expected, MKCoordinateSpanMake(1.25, 2.5));
        [view setRegion:region animated:NO];
        MKCoordinateRegion native = {0};
        static uint64_t hostSelector __attribute__((aligned(8)));
        const uint64_t selector = LC32CachedHostSelector(&hostSelector, @selector(region), YES);
        LC32InvokeHostSelector(view.host_self, selector, &native, sizeof(native), (uint64_t)0);
        MKCoordinateRegion returned = view.region;
        check(fabs(native.center.latitude - expected.latitude) < 0.001 &&
            fabs(native.center.longitude - expected.longitude) < 0.001,
            "set-region-animated-native-center");
        check(returned.center.latitude == native.center.latitude &&
            returned.center.longitude == native.center.longitude &&
            returned.span.latitudeDelta == native.span.latitudeDelta &&
            returned.span.longitudeDelta == native.span.longitudeDelta,
            "region-native-return");
        region.center = CLLocationCoordinate2DMake(-5, 10);
        view.region = region;
        returned = view.region;
        check(fabs(returned.center.latitude + 5) < 0.001 &&
            fabs(returned.center.longitude - 10) < 0.001, "set-region-property");
        [view release];
    }
    return failures != 0;
}
