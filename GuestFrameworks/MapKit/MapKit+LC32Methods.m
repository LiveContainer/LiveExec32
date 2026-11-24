#import <MapKit/MapKit.h>
#import <LC32/LC32.h>

@implementation NSValue (LC32MapKit)
+ (NSValue *)valueWithMKCoordinateSpan:(MKCoordinateSpan)span {
    return [self valueWithBytes:&span objCType:@encode(MKCoordinateSpan)];
}
- (MKCoordinateSpan)MKCoordinateSpanValue {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, @selector(MKCoordinateSpanValue), YES);
    MKCoordinateSpan span = {0};
    LC32InvokeHostSelector(self.host_self, selector, &span, sizeof(span), (uint64_t)0);
    return span;
}
@end

@implementation MKMapView (LC32Region)
- (MKCoordinateRegion)region {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, @selector(region), YES);
    MKCoordinateRegion region = {0};
    LC32InvokeHostSelector(self.host_self, selector, &region, sizeof(region), (uint64_t)0);
    return region;
}
- (void)setRegion:(MKCoordinateRegion)region {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, @selector(setRegion:), NO);
    LC32InvokeHostSelector(self.host_self, selector, LC32HostAggregateArgument(&region), (uint64_t)0);
}
- (void)setRegion:(MKCoordinateRegion)region animated:(BOOL)animated {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, @selector(setRegion:animated:), NO);
    LC32InvokeHostSelector(self.host_self, selector, LC32HostAggregateArgument(&region),
        (uint64_t)animated, (uint64_t)0);
}
@end
