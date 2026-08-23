// Guest constants for CoreLocation.framework
//
// The generated shim emits Objective-C methods but not the C-level
// extern constants.  Provide the ARM32-visible value linked by legacy apps.

#import <CoreLocation/CoreLocation.h>

// CLLocationAccuracy is `double` on both ABIs.
const CLLocationAccuracy kCLLocationAccuracyBest = -1.0;
const CLLocationAccuracy kCLLocationAccuracyNearestTenMeters = 10.0;
const CLLocationAccuracy kCLLocationAccuracyKilometer = 1000.0;
