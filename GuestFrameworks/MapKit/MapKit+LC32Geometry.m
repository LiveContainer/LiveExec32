#import <MapKit/MapKit.h>

#include <math.h>

/* MapKit's projected world is a 2^28-point spherical-Mercator square. */
static const double LC32MapWorldWidth = 268435456.0;
static const double LC32WGS84SemiMajorAxis = 6378137.0;
static const double LC32WGS84EccentricitySquared =
    0.0066943799901413165;

static BOOL LC32MapRectIsNull(MKMapRect rect) {
    return isinf(rect.origin.x) && isinf(rect.origin.y);
}

static double LC32MapLatitudeRadians(double latitude) {
    return latitude * M_PI / 180.0;
}

static double LC32MapMeridionalRadius(double latitude) {
    const double sine = sin(LC32MapLatitudeRadians(latitude));
    const double term = 1.0 -
        LC32WGS84EccentricitySquared * sine * sine;
    return LC32WGS84SemiMajorAxis *
        (1.0 - LC32WGS84EccentricitySquared) /
        (term * sqrt(term));
}

static double LC32MapPrimeVerticalRadius(double latitude) {
    const double sine = sin(LC32MapLatitudeRadians(latitude));
    return LC32WGS84SemiMajorAxis /
        sqrt(1.0 - LC32WGS84EccentricitySquared * sine * sine);
}

MKMapPoint MKMapPointForCoordinate(CLLocationCoordinate2D coordinate) {
    if(!isfinite(coordinate.latitude) ||
            !isfinite(coordinate.longitude) ||
            coordinate.latitude < -90.0 || coordinate.latitude > 90.0 ||
            coordinate.longitude < -180.0 ||
            coordinate.longitude > 180.0) {
        return MKMapPointMake(-1.0, -1.0);
    }

    /* MapKit clips valid polar coordinates before Mercator projection. */
    const double latitude = fmax(-85.0, fmin(85.0, coordinate.latitude));
    const double latitudeRadians = LC32MapLatitudeRadians(latitude);
    return MKMapPointMake(
        (coordinate.longitude + 180.0) * LC32MapWorldWidth / 360.0,
        LC32MapWorldWidth * (0.5 -
            log(tan(M_PI_4 + latitudeRadians / 2.0)) /
                (2.0 * M_PI)));
}

CLLocationCoordinate2D MKCoordinateForMapPoint(MKMapPoint mapPoint) {
    double longitude = fmod(
        mapPoint.x * 360.0 / LC32MapWorldWidth - 180.0, 360.0);
    if(longitude > 180.0) longitude -= 360.0;
    else if(longitude < -180.0) longitude += 360.0;

    const double mercator =
        (mapPoint.y / LC32MapWorldWidth - 0.5) * (2.0 * M_PI);
    const double latitude =
        (M_PI_2 - 2.0 * atan(exp(mercator))) * 180.0 / M_PI;
    return CLLocationCoordinate2DMake(latitude, longitude);
}

CLLocationDistance MKMetersPerMapPointAtLatitude(
        CLLocationDegrees latitude) {
    if(isnan(latitude)) return NAN;
    if(latitude < -90.0 || latitude > 90.0) return INFINITY;
    return LC32MapMeridionalRadius(latitude) *
        cos(LC32MapLatitudeRadians(latitude)) *
        (2.0 * M_PI / LC32MapWorldWidth);
}

double MKMapPointsPerMeterAtLatitude(CLLocationDegrees latitude) {
    return 1.0 / MKMetersPerMapPointAtLatitude(latitude);
}

CLLocationDistance MKMetersBetweenMapPoints(
        MKMapPoint first, MKMapPoint second) {
    const MKMapPoint midpoint = MKMapPointMake(
        (first.x + second.x) / 2.0,
        (first.y + second.y) / 2.0);
    const double latitude = MKCoordinateForMapPoint(midpoint).latitude;
    const double latitudeRadians = LC32MapLatitudeRadians(latitude);
    const double mapRadiansPerPoint = 2.0 * M_PI / LC32MapWorldWidth;
    const double horizontalScale = LC32MapPrimeVerticalRadius(latitude) *
        cos(latitudeRadians) * mapRadiansPerPoint;
    const double verticalScale = LC32MapMeridionalRadius(latitude) *
        cos(latitudeRadians) * mapRadiansPerPoint;
    return hypot((second.x - first.x) * horizontalScale,
        (second.y - first.y) * verticalScale);
}

MKCoordinateRegion MKCoordinateRegionMakeWithDistance(
        CLLocationCoordinate2D centerCoordinate,
        CLLocationDistance latitudinalMeters,
        CLLocationDistance longitudinalMeters) {
    const double latitude = centerCoordinate.latitude;
    const double latitudeRadians = LC32MapLatitudeRadians(latitude);
    const double metersPerLatitudeDegree =
        LC32MapMeridionalRadius(latitude) * M_PI / 180.0;
    const double metersPerLongitudeDegree =
        LC32MapPrimeVerticalRadius(latitude) * cos(latitudeRadians) *
        M_PI / 180.0;
    return MKCoordinateRegionMake(centerCoordinate, MKCoordinateSpanMake(
        latitudinalMeters / metersPerLatitudeDegree,
        longitudinalMeters / metersPerLongitudeDegree));
}

MKMapRect MKMapRectUnion(MKMapRect first, MKMapRect second) {
    if(LC32MapRectIsNull(first)) return second;
    if(LC32MapRectIsNull(second)) return first;
    const double minX = fmin(MKMapRectGetMinX(first),
        MKMapRectGetMinX(second));
    const double minY = fmin(MKMapRectGetMinY(first),
        MKMapRectGetMinY(second));
    const double maxX = fmax(MKMapRectGetMaxX(first),
        MKMapRectGetMaxX(second));
    const double maxY = fmax(MKMapRectGetMaxY(first),
        MKMapRectGetMaxY(second));
    return MKMapRectMake(minX, minY, maxX - minX, maxY - minY);
}

MKMapRect MKMapRectIntersection(MKMapRect first, MKMapRect second) {
    if(LC32MapRectIsNull(first) || LC32MapRectIsNull(second)) {
        return MKMapRectNull;
    }
    const double minX = fmax(MKMapRectGetMinX(first),
        MKMapRectGetMinX(second));
    const double minY = fmax(MKMapRectGetMinY(first),
        MKMapRectGetMinY(second));
    const double maxX = fmin(MKMapRectGetMaxX(first),
        MKMapRectGetMaxX(second));
    const double maxY = fmin(MKMapRectGetMaxY(first),
        MKMapRectGetMaxY(second));
    if(maxX < minX || maxY < minY) return MKMapRectNull;
    return MKMapRectMake(minX, minY, maxX - minX, maxY - minY);
}

MKMapRect MKMapRectInset(MKMapRect rect, double dx, double dy) {
    if(LC32MapRectIsNull(rect)) return rect;
    return MKMapRectMake(rect.origin.x + dx, rect.origin.y + dy,
        rect.size.width - 2.0 * dx, rect.size.height - 2.0 * dy);
}

MKMapRect MKMapRectOffset(MKMapRect rect, double dx, double dy) {
    if(LC32MapRectIsNull(rect)) return rect;
    rect.origin.x += dx;
    rect.origin.y += dy;
    return rect;
}

void MKMapRectDivide(MKMapRect rect, MKMapRect *slice,
        MKMapRect *remainder, double amount, CGRectEdge edge) {
    MKMapRect localSlice = rect;
    MKMapRect localRemainder = rect;
    if(LC32MapRectIsNull(rect)) {
        if(slice) *slice = rect;
        if(remainder) *remainder = rect;
        return;
    }

    switch(edge) {
        case CGRectMinXEdge:
            amount = fmax(0.0, fmin(amount, rect.size.width));
            localSlice.size.width = amount;
            localRemainder.origin.x += amount;
            localRemainder.size.width -= amount;
            break;
        case CGRectMinYEdge:
            amount = fmax(0.0, fmin(amount, rect.size.height));
            localSlice.size.height = amount;
            localRemainder.origin.y += amount;
            localRemainder.size.height -= amount;
            break;
        case CGRectMaxXEdge:
            amount = fmax(0.0, fmin(amount, rect.size.width));
            localSlice.origin.x = MKMapRectGetMaxX(rect) - amount;
            localSlice.size.width = amount;
            localRemainder.size.width -= amount;
            break;
        case CGRectMaxYEdge:
            amount = fmax(0.0, fmin(amount, rect.size.height));
            localSlice.origin.y = MKMapRectGetMaxY(rect) - amount;
            localSlice.size.height = amount;
            localRemainder.size.height -= amount;
            break;
    }
    if(slice) *slice = localSlice;
    if(remainder) *remainder = localRemainder;
}

BOOL MKMapRectContainsPoint(MKMapRect rect, MKMapPoint point) {
    return !LC32MapRectIsNull(rect) &&
        point.x >= MKMapRectGetMinX(rect) &&
        point.y >= MKMapRectGetMinY(rect) &&
        point.x <= MKMapRectGetMaxX(rect) &&
        point.y <= MKMapRectGetMaxY(rect);
}

BOOL MKMapRectContainsRect(MKMapRect outer, MKMapRect inner) {
    if(LC32MapRectIsNull(inner)) return YES;
    if(LC32MapRectIsNull(outer)) return NO;
    return MKMapRectGetMinX(inner) >= MKMapRectGetMinX(outer) &&
        MKMapRectGetMinY(inner) >= MKMapRectGetMinY(outer) &&
        MKMapRectGetMaxX(inner) <= MKMapRectGetMaxX(outer) &&
        MKMapRectGetMaxY(inner) <= MKMapRectGetMaxY(outer);
}

BOOL MKMapRectIntersectsRect(MKMapRect first, MKMapRect second) {
    if(LC32MapRectIsNull(first) || LC32MapRectIsNull(second) ||
            first.size.width <= 0.0 || first.size.height <= 0.0 ||
            second.size.width <= 0.0 || second.size.height <= 0.0) {
        return NO;
    }
    return MKMapRectGetMaxX(first) > MKMapRectGetMinX(second) &&
        MKMapRectGetMaxX(second) > MKMapRectGetMinX(first) &&
        MKMapRectGetMaxY(first) > MKMapRectGetMinY(second) &&
        MKMapRectGetMaxY(second) > MKMapRectGetMinY(first);
}

MKCoordinateRegion MKCoordinateRegionForMapRect(MKMapRect rect) {
    const CLLocationCoordinate2D center = MKCoordinateForMapPoint(
        MKMapPointMake(MKMapRectGetMidX(rect), MKMapRectGetMidY(rect)));
    const CLLocationDegrees north = MKCoordinateForMapPoint(
        MKMapPointMake(MKMapRectGetMidX(rect),
            MKMapRectGetMinY(rect))).latitude;
    const CLLocationDegrees south = MKCoordinateForMapPoint(
        MKMapPointMake(MKMapRectGetMidX(rect),
            MKMapRectGetMaxY(rect))).latitude;
    return MKCoordinateRegionMake(center, MKCoordinateSpanMake(
        north - south, rect.size.width * 360.0 / LC32MapWorldWidth));
}

BOOL MKMapRectSpans180thMeridian(MKMapRect rect) {
    return !LC32MapRectIsNull(rect) &&
        (MKMapRectGetMinX(rect) < 0.0 ||
            MKMapRectGetMaxX(rect) > LC32MapWorldWidth);
}

MKMapRect MKMapRectRemainder(MKMapRect rect) {
    if(!MKMapRectSpans180thMeridian(rect)) return MKMapRectNull;
    const double maxX = MKMapRectGetMaxX(rect);
    if(maxX > LC32MapWorldWidth) {
        return MKMapRectMake(0.0, rect.origin.y,
            maxX - LC32MapWorldWidth, rect.size.height);
    }
    return MKMapRectMake(LC32MapWorldWidth + rect.origin.x,
        rect.origin.y, -rect.origin.x, rect.size.height);
}

CGFloat MKRoadWidthAtZoomScale(MKZoomScale zoomScale) {
    if(isnan(zoomScale) || zoomScale < 0.0f) return NAN;
    if(zoomScale == 0.0f) return INFINITY;
    if(isinf(zoomScale)) return 0.0f;

    /* MapKit uses a small screen-width table keyed by the integral zoom
     * level, then converts that width back into map points. */
    const int level = (int)ceil(log2((double)zoomScale));
    double screenWidth;
    if(level >= 0) screenWidth = 21.0;
    else if(level >= -1) screenWidth = 16.0;
    else if(level >= -2) screenWidth = 15.0;
    else if(level >= -3) screenWidth = 12.0;
    else if(level >= -4) screenWidth = 11.0;
    else if(level >= -5) screenWidth = 9.0;
    else if(level >= -6) screenWidth = 7.0;
    else if(level >= -8) screenWidth = 6.0;
    else if(level >= -10) screenWidth = 4.0;
    else if(level >= -13) screenWidth = 3.0;
    else screenWidth = 2.0;
    return (CGFloat)(screenWidth / zoomScale);
}
