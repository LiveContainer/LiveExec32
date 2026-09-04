// Guest constants for CoreLocation.framework
//
// The generated shim emits Objective-C methods but not the C-level
// extern constants.  Provide the ARM32-visible value linked by legacy apps.

#import <CoreLocation/CoreLocation.h>
#include <float.h>
#include <math.h>

// CLLocationAccuracy is `double` on both ABIs.
const CLLocationAccuracy kCLLocationAccuracyBest = -1.0;
const CLLocationAccuracy kCLLocationAccuracyBestForNavigation = -2.0;
const CLLocationAccuracy kCLLocationAccuracyNearestTenMeters = 10.0;
const CLLocationAccuracy kCLLocationAccuracyHundredMeters = 100.0;
const CLLocationAccuracy kCLLocationAccuracyKilometer = 1000.0;
const CLLocationAccuracy kCLLocationAccuracyThreeKilometers = 3000.0;

const CLLocationDistance CLLocationDistanceMax = DBL_MAX;
const NSTimeInterval CLTimeIntervalMax = DBL_MAX;
const CLLocationDegrees kCLHeadingFilterNone = -1.0;
const CLLocationDistance kCLDistanceFilterNone = -1.0;
const CLLocationCoordinate2D kCLLocationCoordinate2DInvalid = {-180.0, -180.0};

NSString *const kCLErrorDomain = @"kCLErrorDomain";
NSString *const kCLErrorUserInfoAlternateRegionKey =
    @"kCLErrorUserInfoAlternateRegionKey";

BOOL CLLocationCoordinate2DIsValid(CLLocationCoordinate2D coordinate) {
    return isfinite(coordinate.latitude) &&
        isfinite(coordinate.longitude) &&
        coordinate.latitude >= -90.0 && coordinate.latitude <= 90.0 &&
        coordinate.longitude >= -180.0 && coordinate.longitude <= 180.0;
}

CLLocationCoordinate2D CLLocationCoordinate2DMake(
    CLLocationDegrees latitude, CLLocationDegrees longitude) {
    return (CLLocationCoordinate2D){latitude, longitude};
}
