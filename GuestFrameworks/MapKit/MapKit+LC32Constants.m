#import <MapKit/MapKit.h>

#define LC32_MAPKIT_STRING(symbol, value) \
    NSString *const LC32_MAPKIT_##symbol __asm__("_" #symbol) = value;

LC32_MAPKIT_STRING(MKAnnotationCalloutInfoDidChangeNotification,
    @"MKAnnotationCalloutInfoDidChangeNotification")
LC32_MAPKIT_STRING(MKErrorDomain, @"MKErrorDomain")
LC32_MAPKIT_STRING(MKLaunchOptionsCameraKey, @"MKLaunchOptionsCameraKey")
LC32_MAPKIT_STRING(MKLaunchOptionsDirectionsModeDefault,
    @"MKLaunchOptionsDirectionsModeDefault")
LC32_MAPKIT_STRING(MKLaunchOptionsDirectionsModeDriving,
    @"MKLaunchOptionsDirectionsModeDriving")
LC32_MAPKIT_STRING(MKLaunchOptionsDirectionsModeKey,
    @"MKLaunchOptionsDirectionsMode")
LC32_MAPKIT_STRING(MKLaunchOptionsDirectionsModeTransit,
    @"MKLaunchOptionsDirectionsModeTransit")
LC32_MAPKIT_STRING(MKLaunchOptionsDirectionsModeWalking,
    @"MKLaunchOptionsDirectionsModeWalking")
LC32_MAPKIT_STRING(MKLaunchOptionsMapCenterKey, @"MKLaunchOptionsMapCenter")
LC32_MAPKIT_STRING(MKLaunchOptionsMapSpanKey, @"MKLaunchOptionsMapSpan")
LC32_MAPKIT_STRING(MKLaunchOptionsMapTypeKey, @"MKLaunchOptionsMapType")
LC32_MAPKIT_STRING(MKLaunchOptionsShowsTrafficKey,
    @"MKLaunchOptionsShowsTraffic")

#undef LC32_MAPKIT_STRING

const MKMapSize LC32_MKMapSizeWorld __asm__("_MKMapSizeWorld") = {
    268435456.0, 268435456.0
};
const MKMapRect LC32_MKMapRectWorld __asm__("_MKMapRectWorld") = {
    {0.0, 0.0}, {268435456.0, 268435456.0}
};
const MKMapRect LC32_MKMapRectNull __asm__("_MKMapRectNull") = {
    {INFINITY, INFINITY}, {0.0, 0.0}
};
