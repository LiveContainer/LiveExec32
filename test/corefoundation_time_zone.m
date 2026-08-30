#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL stringEquals(CFStringRef string, NSString *expected) {
    return string && [(NSString *)string isEqualToString:expected];
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    const CFAbsoluteTime referenceDate = 0.0;

    CFTimeZoneRef gmt = CFTimeZoneCreateWithTimeIntervalFromGMT(
        kCFAllocatorDefault, 0.0);
    CFTimeZoneRef namedGMT = CFTimeZoneCreateWithName(
        kCFAllocatorDefault, CFSTR("GMT"), false);
    check("time-zone-create", gmt && namedGMT &&
        stringEquals(CFTimeZoneGetName(gmt), @"GMT") &&
        stringEquals(CFTimeZoneGetName(namedGMT), @"GMT"));
    check("time-zone-type-id", gmt && CFTimeZoneGetTypeID() != 0 &&
        CFGetTypeID(gmt) == CFTimeZoneGetTypeID());
    check("time-zone-gmt-offset", gmt &&
        CFTimeZoneGetSecondsFromGMT(gmt, referenceDate) == 0.0 &&
        !CFTimeZoneIsDaylightSavingTime(gmt, referenceDate) &&
        CFTimeZoneGetDaylightSavingTimeOffset(gmt, referenceDate) == 0.0 &&
        CFTimeZoneGetNextDaylightSavingTimeTransition(
            gmt, referenceDate) == 0.0);
    CFTimeZoneRef negativeFraction =
        CFTimeZoneCreateWithTimeIntervalFromGMT(
            kCFAllocatorDefault, -1.1);
    check("time-zone-fractional-offset-floor", negativeFraction &&
        CFTimeZoneGetSecondsFromGMT(
            negativeFraction, referenceDate) == -2.0);

    CFStringRef abbreviation = gmt
        ? CFTimeZoneCopyAbbreviation(gmt, referenceDate) : NULL;
    check("time-zone-abbreviation",
        stringEquals(abbreviation, @"GMT"));
    CFDataRef data = gmt ? CFTimeZoneGetData(gmt) : NULL;
    CFTimeZoneRef recreated = data ? CFTimeZoneCreate(
        kCFAllocatorDefault, CFTimeZoneGetName(gmt), data) : NULL;
    check("time-zone-create-with-data", recreated &&
        CFTimeZoneGetSecondsFromGMT(recreated, referenceDate) == 0.0);

    CFLocaleRef locale = CFLocaleCopyCurrent();
    CFStringRef localizedName = gmt ? CFTimeZoneCopyLocalizedName(
        gmt, kCFTimeZoneNameStyleStandard, locale) : NULL;
    check("time-zone-localized-name", localizedName &&
        CFStringGetLength(localizedName) != 0);

    CFArrayRef knownNames = CFTimeZoneCopyKnownNames();
    CFDictionaryRef abbreviations =
        CFTimeZoneCopyAbbreviationDictionary();
    check("time-zone-known-names", knownNames &&
        CFArrayGetCount(knownNames) != 0);
    check("time-zone-abbreviation-dictionary", abbreviations &&
        CFDictionaryGetCount(abbreviations) != 0);
    if(abbreviations) CFTimeZoneSetAbbreviationDictionary(abbreviations);

    CFTimeZoneRef originalDefault = CFTimeZoneCopyDefault();
    if(gmt) CFTimeZoneSetDefault(gmt);
    CFTimeZoneRef changedDefault = CFTimeZoneCopyDefault();
    check("time-zone-set-default", changedDefault &&
        stringEquals(CFTimeZoneGetName(changedDefault), @"GMT"));
    if(originalDefault) CFTimeZoneSetDefault(originalDefault);

    CFTimeZoneResetSystem();
    CFTimeZoneRef system = CFTimeZoneCopySystem();
    check("time-zone-copy-system", system != NULL);
    check("time-zone-notification-constant",
        kCFTimeZoneSystemTimeZoneDidChangeNotification != NULL);

    if(gmt) {
        CFRelease(gmt);
        gmt = NULL;
    }
    check("time-zone-copy-ownership", abbreviation &&
        stringEquals(abbreviation, @"GMT") && recreated);

    if(system) CFRelease(system);
    if(changedDefault) CFRelease(changedDefault);
    if(originalDefault) CFRelease(originalDefault);
    if(abbreviations) CFRelease(abbreviations);
    if(knownNames) CFRelease(knownNames);
    if(localizedName) CFRelease(localizedName);
    if(locale) CFRelease(locale);
    if(recreated) CFRelease(recreated);
    if(abbreviation) CFRelease(abbreviation);
    if(namedGMT) CFRelease(namedGMT);
    if(negativeFraction) CFRelease(negativeFraction);

    [pool drain];
    return failures != 0;
}
