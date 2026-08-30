#import <CoreFoundation/CoreFoundation+LC32.h>

#include <math.h>

const CFNotificationName kCFTimeZoneSystemTimeZoneDidChangeNotification =
    CFSTR("kCFTimeZoneSystemTimeZoneDidChangeNotification");

static NSDate *LC32TimeZoneDate(CFAbsoluteTime absoluteTime) {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

CFTypeID CFTimeZoneGetTypeID(void) {
    return CFGetTypeID((CFTypeRef)[NSTimeZone systemTimeZone]);
}

CFTimeZoneRef CFTimeZoneCopySystem(void) {
    return (CFTimeZoneRef)[[NSTimeZone systemTimeZone] copy];
}

void CFTimeZoneResetSystem(void) {
    [NSTimeZone resetSystemTimeZone];
}

CFTimeZoneRef CFTimeZoneCopyDefault(void) {
    return (CFTimeZoneRef)[[NSTimeZone defaultTimeZone] copy];
}

void CFTimeZoneSetDefault(CFTimeZoneRef timeZone) {
    if(timeZone) [NSTimeZone setDefaultTimeZone:(NSTimeZone *)timeZone];
}

CFArrayRef CFTimeZoneCopyKnownNames(void) {
    return (CFArrayRef)[[NSTimeZone knownTimeZoneNames] copy];
}

CFDictionaryRef CFTimeZoneCopyAbbreviationDictionary(void) {
    return (CFDictionaryRef)[[NSTimeZone abbreviationDictionary] copy];
}

void CFTimeZoneSetAbbreviationDictionary(CFDictionaryRef dictionary) {
    if(dictionary) [NSTimeZone
        setAbbreviationDictionary:(NSDictionary *)dictionary];
}

CFTimeZoneRef CFTimeZoneCreate(CFAllocatorRef allocator, CFStringRef name,
                               CFDataRef data) {
    (void)allocator;
    if(!name || !data) return NULL;
    return (CFTimeZoneRef)[[NSTimeZone
        timeZoneWithName:(NSString *)name data:(NSData *)data] copy];
}

CFTimeZoneRef CFTimeZoneCreateWithTimeIntervalFromGMT(
        CFAllocatorRef allocator, CFTimeInterval interval) {
    (void)allocator;
    if(!isfinite(interval)) return NULL;
    return (CFTimeZoneRef)[[NSTimeZone
        timeZoneForSecondsFromGMT:(NSInteger)floor(interval)] copy];
}

CFTimeZoneRef CFTimeZoneCreateWithName(CFAllocatorRef allocator,
                                       CFStringRef name,
                                       Boolean tryAbbreviation) {
    (void)allocator;
    if(!name) return NULL;
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:(NSString *)name];
    if(!timeZone && tryAbbreviation)
        timeZone = [NSTimeZone timeZoneWithAbbreviation:(NSString *)name];
    return (CFTimeZoneRef)[timeZone copy];
}

CFStringRef CFTimeZoneGetName(CFTimeZoneRef timeZone) {
    return timeZone ? (CFStringRef)[(NSTimeZone *)timeZone name] : NULL;
}

CFDataRef CFTimeZoneGetData(CFTimeZoneRef timeZone) {
    return timeZone ? (CFDataRef)[(NSTimeZone *)timeZone data] : NULL;
}

CFTimeInterval CFTimeZoneGetSecondsFromGMT(CFTimeZoneRef timeZone,
                                           CFAbsoluteTime absoluteTime) {
    return timeZone ? (CFTimeInterval)[(NSTimeZone *)timeZone
        secondsFromGMTForDate:LC32TimeZoneDate(absoluteTime)] : 0.0;
}

CFStringRef CFTimeZoneCopyAbbreviation(CFTimeZoneRef timeZone,
                                       CFAbsoluteTime absoluteTime) {
    return timeZone ? (CFStringRef)[[(NSTimeZone *)timeZone
        abbreviationForDate:LC32TimeZoneDate(absoluteTime)] copy] : NULL;
}

Boolean CFTimeZoneIsDaylightSavingTime(CFTimeZoneRef timeZone,
                                       CFAbsoluteTime absoluteTime) {
    return timeZone && [(NSTimeZone *)timeZone
        isDaylightSavingTimeForDate:LC32TimeZoneDate(absoluteTime)];
}

CFTimeInterval CFTimeZoneGetDaylightSavingTimeOffset(
        CFTimeZoneRef timeZone, CFAbsoluteTime absoluteTime) {
    return timeZone ? [(NSTimeZone *)timeZone
        daylightSavingTimeOffsetForDate:LC32TimeZoneDate(absoluteTime)] : 0.0;
}

CFAbsoluteTime CFTimeZoneGetNextDaylightSavingTimeTransition(
        CFTimeZoneRef timeZone, CFAbsoluteTime absoluteTime) {
    if(!timeZone) return 0.0;
    NSDate *transition = [(NSTimeZone *)timeZone
        nextDaylightSavingTimeTransitionAfterDate:
            LC32TimeZoneDate(absoluteTime)];
    return transition ? transition.timeIntervalSinceReferenceDate : 0.0;
}

CFStringRef CFTimeZoneCopyLocalizedName(CFTimeZoneRef timeZone,
                                        CFTimeZoneNameStyle style,
                                        CFLocaleRef locale) {
    if(!timeZone || !locale) return NULL;
    _Static_assert(sizeof(CFTimeZoneNameStyle) == sizeof(NSTimeZoneNameStyle),
        "time-zone name styles must share their ARM32 ABI");
    return (CFStringRef)[[(NSTimeZone *)timeZone
        localizedName:(NSTimeZoneNameStyle)style locale:(NSLocale *)locale]
        copy];
}
