#import <CoreFoundation/CoreFoundation+LC32.h>

static NSDate *LC32CalendarDate(CFAbsoluteTime absoluteTime) {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

CFTypeID CFCalendarGetTypeID(void) {
    return CFGetTypeID((CFTypeRef)[NSCalendar currentCalendar]);
}

CFCalendarRef CFCalendarCopyCurrent(void) {
    return (CFCalendarRef)[[NSCalendar currentCalendar] copy];
}

CFCalendarRef CFCalendarCreateWithIdentifier(
        CFAllocatorRef allocator, CFCalendarIdentifier identifier) {
    (void)allocator;
    if(!identifier) return NULL;
    return (CFCalendarRef)[[NSCalendar alloc]
        initWithCalendarIdentifier:(NSString *)identifier];
}

CFCalendarIdentifier CFCalendarGetIdentifier(CFCalendarRef calendar) {
    return calendar
        ? (CFCalendarIdentifier)[(NSCalendar *)calendar calendarIdentifier]
        : NULL;
}

CFLocaleRef CFCalendarCopyLocale(CFCalendarRef calendar) {
    return calendar ? (CFLocaleRef)[[(NSCalendar *)calendar locale] copy]
                    : NULL;
}

void CFCalendarSetLocale(CFCalendarRef calendar, CFLocaleRef locale) {
    if(calendar && locale)
        [(NSCalendar *)calendar setLocale:(NSLocale *)locale];
}

CFTimeZoneRef CFCalendarCopyTimeZone(CFCalendarRef calendar) {
    return calendar ? (CFTimeZoneRef)[[(NSCalendar *)calendar timeZone] copy]
                    : NULL;
}

void CFCalendarSetTimeZone(CFCalendarRef calendar,
                           CFTimeZoneRef timeZone) {
    if(calendar && timeZone)
        [(NSCalendar *)calendar setTimeZone:(NSTimeZone *)timeZone];
}

CFIndex CFCalendarGetFirstWeekday(CFCalendarRef calendar) {
    return calendar ? (CFIndex)[(NSCalendar *)calendar firstWeekday] : 0;
}

void CFCalendarSetFirstWeekday(CFCalendarRef calendar,
                               CFIndex firstWeekday) {
    if(calendar && firstWeekday >= 0)
        [(NSCalendar *)calendar setFirstWeekday:(NSUInteger)firstWeekday];
}

CFIndex CFCalendarGetMinimumDaysInFirstWeek(CFCalendarRef calendar) {
    return calendar
        ? (CFIndex)[(NSCalendar *)calendar minimumDaysInFirstWeek] : 0;
}

void CFCalendarSetMinimumDaysInFirstWeek(CFCalendarRef calendar,
                                         CFIndex minimumDays) {
    if(calendar && minimumDays >= 0) [(NSCalendar *)calendar
        setMinimumDaysInFirstWeek:(NSUInteger)minimumDays];
}

CFRange CFCalendarGetMinimumRangeOfUnit(CFCalendarRef calendar,
                                        CFCalendarUnit unit) {
    if(!calendar) return CFRangeMake(kCFNotFound, 0);
    const NSRange range = [(NSCalendar *)calendar
        minimumRangeOfUnit:(NSCalendarUnit)unit];
    return CFRangeMake((CFIndex)range.location, (CFIndex)range.length);
}

CFRange CFCalendarGetMaximumRangeOfUnit(CFCalendarRef calendar,
                                        CFCalendarUnit unit) {
    if(!calendar) return CFRangeMake(kCFNotFound, 0);
    const NSRange range = [(NSCalendar *)calendar
        maximumRangeOfUnit:(NSCalendarUnit)unit];
    return CFRangeMake((CFIndex)range.location, (CFIndex)range.length);
}

CFRange CFCalendarGetRangeOfUnit(CFCalendarRef calendar,
                                 CFCalendarUnit smallerUnit,
                                 CFCalendarUnit biggerUnit,
                                 CFAbsoluteTime absoluteTime) {
    if(!calendar) return CFRangeMake(kCFNotFound, 0);
    const NSRange range = [(NSCalendar *)calendar
        rangeOfUnit:(NSCalendarUnit)smallerUnit
        inUnit:(NSCalendarUnit)biggerUnit
        forDate:LC32CalendarDate(absoluteTime)];
    return CFRangeMake((CFIndex)range.location, (CFIndex)range.length);
}

CFIndex CFCalendarGetOrdinalityOfUnit(CFCalendarRef calendar,
                                      CFCalendarUnit smallerUnit,
                                      CFCalendarUnit biggerUnit,
                                      CFAbsoluteTime absoluteTime) {
    return calendar ? (CFIndex)[(NSCalendar *)calendar
        ordinalityOfUnit:(NSCalendarUnit)smallerUnit
        inUnit:(NSCalendarUnit)biggerUnit
        forDate:LC32CalendarDate(absoluteTime)] : kCFNotFound;
}
