#import <CoreFoundation/CoreFoundation+LC32.h>

static uint64_t LC32CFDoubleBits(double value) {
    union {
        double value;
        uint64_t bits;
    } representation = { .value = value };
    return representation.bits;
}

CFDateRef CFDateCreate(CFAllocatorRef allocator, CFAbsoluteTime at) {
    (void)allocator;
    return (CFDateRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateCreate, LC32CFDoubleBits(at));
}

CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef date) {
    if(!date) return 0.0;
    CFAbsoluteTime result = 0.0;
    if(!LC32_CF_CALL(LC32CoreFoundationOpDateGetAbsoluteTime,
            LC32_CF_HOST(date), LC32_CF_U32((uintptr_t)&result))) {
        return 0.0;
    }
    return result;
}

CFTimeInterval CFDateGetTimeIntervalSinceDate(CFDateRef date,
                                               CFDateRef otherDate) {
    if(!date || !otherDate) return 0.0;
    CFTimeInterval result = 0.0;
    if(!LC32_CF_CALL(LC32CoreFoundationOpDateGetTimeIntervalSinceDate,
            LC32_CF_HOST(date), LC32_CF_HOST(otherDate),
            LC32_CF_U32((uintptr_t)&result))) {
        return 0.0;
    }
    return result;
}

CFComparisonResult CFDateCompare(CFDateRef date, CFDateRef otherDate,
                                 void *context) {
    (void)context;
    if(!date || !otherDate) return kCFCompareEqualTo;
    return (CFComparisonResult)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpDateCompare,
        LC32_CF_HOST(date), LC32_CF_HOST(otherDate));
}

SInt32 CFAbsoluteTimeGetDayOfWeek(CFAbsoluteTime at, CFTimeZoneRef tz) {
    return (SInt32)LC32_CF_CALL(
        LC32CoreFoundationOpAbsoluteTimeGetDayOfWeek,
        LC32CFDoubleBits(at), LC32_CF_HOST(tz));
}

SInt32 CFAbsoluteTimeGetDayOfYear(CFAbsoluteTime at, CFTimeZoneRef tz) {
    return (SInt32)LC32_CF_CALL(
        LC32CoreFoundationOpAbsoluteTimeGetDayOfYear,
        LC32CFDoubleBits(at), LC32_CF_HOST(tz));
}

SInt32 CFAbsoluteTimeGetWeekOfYear(CFAbsoluteTime at, CFTimeZoneRef tz) {
    return (SInt32)LC32_CF_CALL(
        LC32CoreFoundationOpAbsoluteTimeGetWeekOfYear,
        LC32CFDoubleBits(at), LC32_CF_HOST(tz));
}

CFDateFormatterRef CFDateFormatterCreate(CFAllocatorRef allocator,
        CFLocaleRef locale, CFDateFormatterStyle dateStyle,
        CFDateFormatterStyle timeStyle) {
    (void)allocator;
    return (CFDateFormatterRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterCreate,
        LC32_CF_HOST(locale), LC32_CF_U32(dateStyle),
        LC32_CF_U32(timeStyle));
}

CFDateFormatterRef CFDateFormatterCreateISO8601Formatter(
        CFAllocatorRef allocator, CFISO8601DateFormatOptions formatOptions) {
    (void)allocator;
    return (CFDateFormatterRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterCreateISO8601Formatter,
        LC32_CF_U32(formatOptions));
}

CFTypeID CFDateFormatterGetTypeID(void) {
    CFDateFormatterRef formatter = CFDateFormatterCreate(
        kCFAllocatorDefault, CFLocaleGetSystem(),
        kCFDateFormatterNoStyle, kCFDateFormatterNoStyle);
    if(!formatter) return 0;
    const CFTypeID typeID = CFGetTypeID(formatter);
    CFRelease(formatter);
    return typeID;
}

CFLocaleRef CFDateFormatterGetLocale(CFDateFormatterRef formatter) {
    return formatter ? (CFLocaleRef)[(NSDateFormatter *)formatter locale]
                     : NULL;
}

CFDateFormatterStyle CFDateFormatterGetDateStyle(
        CFDateFormatterRef formatter) {
    return formatter
        ? (CFDateFormatterStyle)[(NSDateFormatter *)formatter dateStyle]
        : kCFDateFormatterNoStyle;
}

CFDateFormatterStyle CFDateFormatterGetTimeStyle(
        CFDateFormatterRef formatter) {
    return formatter
        ? (CFDateFormatterStyle)[(NSDateFormatter *)formatter timeStyle]
        : kCFDateFormatterNoStyle;
}

CFStringRef CFDateFormatterGetFormat(CFDateFormatterRef formatter) {
    return formatter ? (CFStringRef)[(NSDateFormatter *)formatter dateFormat]
                     : NULL;
}

void CFDateFormatterSetFormat(CFDateFormatterRef formatter,
                              CFStringRef formatString) {
    if(!formatter || !formatString) return;
    LC32_CF_CALL(LC32CoreFoundationOpDateFormatterSetFormat,
        LC32_CF_HOST(formatter), LC32_CF_HOST(formatString));
}

CFStringRef CFDateFormatterCreateStringWithAbsoluteTime(
        CFAllocatorRef allocator, CFDateFormatterRef formatter,
        CFAbsoluteTime at) {
    (void)allocator;
    if(!formatter) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterCreateStringWithAbsoluteTime,
        LC32_CF_HOST(formatter), LC32CFDoubleBits(at));
}

CFStringRef CFDateFormatterCreateStringWithDate(
        CFAllocatorRef allocator, CFDateFormatterRef formatter,
        CFDateRef date) {
    return date ? CFDateFormatterCreateStringWithAbsoluteTime(
        allocator, formatter, CFDateGetAbsoluteTime(date)) : NULL;
}

CFDateRef CFDateFormatterCreateDateFromString(
        CFAllocatorRef allocator, CFDateFormatterRef formatter,
        CFStringRef string, CFRange *range) {
    (void)allocator;
    if(!formatter || !string) return NULL;
    return (CFDateRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterCreateDateFromString,
        LC32_CF_HOST(formatter), LC32_CF_HOST(string),
        LC32_CF_U32((uintptr_t)range));
}

Boolean CFDateFormatterGetAbsoluteTimeFromString(
        CFDateFormatterRef formatter, CFStringRef string,
        CFRange *range, CFAbsoluteTime *absoluteTime) {
    if(!formatter || !string) return false;
    return LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterGetAbsoluteTimeFromString,
        LC32_CF_HOST(formatter), LC32_CF_HOST(string),
        LC32_CF_U32((uintptr_t)range),
        LC32_CF_U32((uintptr_t)absoluteTime));
}

CFStringRef CFDateFormatterCreateDateFormatFromTemplate(
        CFAllocatorRef allocator, CFStringRef templateString,
        CFOptionFlags options, CFLocaleRef locale) {
    (void)allocator;
    if(!templateString) return NULL;
    return (CFStringRef)[[NSDateFormatter
        dateFormatFromTemplate:(NSString *)templateString
        options:(NSUInteger)options locale:(NSLocale *)locale] copy];
}

#define LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(KEY, GETTER, SETTER) \
    if(CFEqual(propertyName, KEY)) { \
        [nativeFormatter SETTER:(id)value]; \
        return; \
    }

void CFDateFormatterSetProperty(CFDateFormatterRef formatter,
                                CFDateFormatterKey propertyName,
                                CFTypeRef value) {
    if(!formatter || !propertyName || !value) return;
    NSDateFormatter *nativeFormatter = (NSDateFormatter *)formatter;

    if(CFEqual(propertyName, kCFDateFormatterIsLenient)) {
        nativeFormatter.lenient = [(NSNumber *)value boolValue];
        return;
    }
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterTimeZone, timeZone, setTimeZone)
    if(CFEqual(propertyName, kCFDateFormatterCalendarName)) {
        NSCalendar *calendar = [[NSCalendar alloc]
            initWithCalendarIdentifier:(NSString *)value];
        if(calendar) nativeFormatter.calendar = calendar;
        [calendar release];
        return;
    }
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterDefaultFormat, dateFormat, setDateFormat)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterTwoDigitStartDate, twoDigitStartDate,
        setTwoDigitStartDate)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterDefaultDate, defaultDate, setDefaultDate)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterCalendar, calendar, setCalendar)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterEraSymbols, eraSymbols, setEraSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterMonthSymbols, monthSymbols, setMonthSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterShortMonthSymbols, shortMonthSymbols,
        setShortMonthSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterWeekdaySymbols, weekdaySymbols, setWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterShortWeekdaySymbols, shortWeekdaySymbols,
        setShortWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterAMSymbol, AMSymbol, setAMSymbol)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterPMSymbol, PMSymbol, setPMSymbol)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterLongEraSymbols, longEraSymbols, setLongEraSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortMonthSymbols, veryShortMonthSymbols,
        setVeryShortMonthSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterStandaloneMonthSymbols, standaloneMonthSymbols,
        setStandaloneMonthSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterShortStandaloneMonthSymbols,
        shortStandaloneMonthSymbols, setShortStandaloneMonthSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortStandaloneMonthSymbols,
        veryShortStandaloneMonthSymbols, setVeryShortStandaloneMonthSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortWeekdaySymbols, veryShortWeekdaySymbols,
        setVeryShortWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterStandaloneWeekdaySymbols, standaloneWeekdaySymbols,
        setStandaloneWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterShortStandaloneWeekdaySymbols,
        shortStandaloneWeekdaySymbols, setShortStandaloneWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortStandaloneWeekdaySymbols,
        veryShortStandaloneWeekdaySymbols,
        setVeryShortStandaloneWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterQuarterSymbols, quarterSymbols, setQuarterSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterShortQuarterSymbols, shortQuarterSymbols,
        setShortQuarterSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterStandaloneQuarterSymbols, standaloneQuarterSymbols,
        setStandaloneQuarterSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterShortStandaloneQuarterSymbols,
        shortStandaloneQuarterSymbols, setShortStandaloneQuarterSymbols)
    LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY(
        kCFDateFormatterGregorianStartDate, gregorianStartDate,
        setGregorianStartDate)
    if(CFEqual(propertyName,
               kCFDateFormatterDoesRelativeDateFormattingKey)) {
        nativeFormatter.doesRelativeDateFormatting =
            [(NSNumber *)value boolValue];
    }
}

#undef LC32_CF_DATE_FORMATTER_OBJECT_PROPERTY

#define LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(KEY, GETTER) \
    if(CFEqual(propertyName, KEY)) \
        return (CFTypeRef)[[nativeFormatter GETTER] copy];

CFTypeRef CFDateFormatterCopyProperty(CFDateFormatterRef formatter,
                                      CFDateFormatterKey propertyName) {
    if(!formatter || !propertyName) return NULL;
    NSDateFormatter *nativeFormatter = (NSDateFormatter *)formatter;

    if(CFEqual(propertyName, kCFDateFormatterIsLenient))
        return (CFTypeRef)[@(nativeFormatter.isLenient) retain];
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterTimeZone, timeZone)
    if(CFEqual(propertyName, kCFDateFormatterCalendarName))
        return (CFTypeRef)[nativeFormatter.calendar.calendarIdentifier copy];
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterDefaultFormat, dateFormat)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterTwoDigitStartDate, twoDigitStartDate)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterDefaultDate, defaultDate)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterCalendar, calendar)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterEraSymbols, eraSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterMonthSymbols, monthSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterShortMonthSymbols, shortMonthSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterWeekdaySymbols, weekdaySymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterShortWeekdaySymbols, shortWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterAMSymbol, AMSymbol)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterPMSymbol, PMSymbol)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterLongEraSymbols, longEraSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortMonthSymbols, veryShortMonthSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterStandaloneMonthSymbols, standaloneMonthSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterShortStandaloneMonthSymbols,
        shortStandaloneMonthSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortStandaloneMonthSymbols,
        veryShortStandaloneMonthSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortWeekdaySymbols, veryShortWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterStandaloneWeekdaySymbols, standaloneWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterShortStandaloneWeekdaySymbols,
        shortStandaloneWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterVeryShortStandaloneWeekdaySymbols,
        veryShortStandaloneWeekdaySymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterQuarterSymbols, quarterSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterShortQuarterSymbols, shortQuarterSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterStandaloneQuarterSymbols, standaloneQuarterSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterShortStandaloneQuarterSymbols,
        shortStandaloneQuarterSymbols)
    LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFDateFormatterGregorianStartDate, gregorianStartDate)
    if(CFEqual(propertyName,
               kCFDateFormatterDoesRelativeDateFormattingKey))
        return (CFTypeRef)[@(nativeFormatter.doesRelativeDateFormatting)
            retain];
    return NULL;
}

#undef LC32_CF_DATE_FORMATTER_COPY_OBJECT_PROPERTY
