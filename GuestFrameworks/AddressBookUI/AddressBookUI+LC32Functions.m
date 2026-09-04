#import <AddressBookUI/AddressBookUI.h>
#import <objc/runtime.h>

static NSString *LC32AddressValue(NSDictionary *address, NSString *key) {
    id value = [address objectForKey:key];
    if(!value || value == [objc_getClass("NSNull") null]) return nil;
    return [value isKindOfClass:objc_getClass("NSString")]
        ? value : [value description];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
NSString *ABCreateStringWithAddressDictionary(
        NSDictionary *address, BOOL addCountryName) {
    id lines = [objc_getClass("NSMutableArray") array];
    NSString *street = LC32AddressValue(address, @"Street");
    NSString *city = LC32AddressValue(address, @"City");
    NSString *state = LC32AddressValue(address, @"State");
    NSString *postalCode = LC32AddressValue(address, @"ZIP");
    NSString *country = LC32AddressValue(address, @"Country");
    NSString *countryCode = LC32AddressValue(address, @"CountryCode");

    if(street.length) [lines addObject:street];

    id locality = [[objc_getClass("NSMutableString") alloc] init];
    if(city.length) [locality appendString:city];
    if(state.length) {
        if([locality length]) [locality appendString:@", "];
        [locality appendString:state];
    }
    if(postalCode.length) {
        if([locality length]) [locality appendString:@" "];
        [locality appendString:postalCode];
    }
    if([locality length]) [lines addObject:locality];
    [locality release];

    if(country.length) {
        [lines addObject:country];
    } else if(addCountryName && countryCode.length) {
        id locale = [objc_getClass("NSLocale") currentLocale];
        NSString *countryName = [locale
            displayNameForKey:@"kCFLocaleCountryCodeKey"
            value:countryCode];
        [lines addObject:countryName.length ? countryName : countryCode];
    }

    /* The public Create-named API returns an owning reference. */
    return [[lines componentsJoinedByString:@"\n"] retain];
}
#pragma clang diagnostic pop
