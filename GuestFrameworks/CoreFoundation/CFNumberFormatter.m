#import <CoreFoundation/CoreFoundation+LC32.h>

Boolean CFNumberFormatterGetDecimalInfoForCurrencyCode(
        CFStringRef currencyCode, int32_t *defaultFractionDigits,
        double *roundingIncrement) {
    if(defaultFractionDigits) *defaultFractionDigits = 0;
    if(roundingIncrement) *roundingIncrement = 0.0;
    if(!currencyCode || !defaultFractionDigits || !roundingIncrement)
        return false;
    return LC32_CF_CALL(
        LC32CoreFoundationOpNumberFormatterGetDecimalInfoForCurrencyCode,
        LC32_CF_HOST(currencyCode),
        LC32_CF_U32((uintptr_t)defaultFractionDigits),
        LC32_CF_U32((uintptr_t)roundingIncrement)) != 0;
}

static NSNumberFormatter *LC32NumberFormatter(CFNumberFormatterRef formatter) {
    return (NSNumberFormatter *)formatter;
}

CFTypeID CFNumberFormatterGetTypeID(void) {
    NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init]
        autorelease];
    return CFGetTypeID((CFTypeRef)formatter);
}

CFNumberFormatterRef CFNumberFormatterCreate(
        CFAllocatorRef allocator, CFLocaleRef locale,
        CFNumberFormatterStyle style) {
    (void)allocator;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    if(locale) formatter.locale = (NSLocale *)locale;
    formatter.numberStyle = (NSNumberFormatterStyle)style;
    return (CFNumberFormatterRef)formatter;
}

CFLocaleRef CFNumberFormatterGetLocale(CFNumberFormatterRef formatter) {
    return formatter ? (CFLocaleRef)LC32NumberFormatter(formatter).locale
                     : NULL;
}

CFNumberFormatterStyle CFNumberFormatterGetStyle(
        CFNumberFormatterRef formatter) {
    return formatter ? (CFNumberFormatterStyle)
        LC32NumberFormatter(formatter).numberStyle : kCFNumberFormatterNoStyle;
}

CFStringRef CFNumberFormatterGetFormat(CFNumberFormatterRef formatter) {
    return formatter
        ? (CFStringRef)LC32NumberFormatter(formatter).positiveFormat : NULL;
}

void CFNumberFormatterSetFormat(CFNumberFormatterRef formatter,
                                CFStringRef formatString) {
    if(formatter && formatString)
        LC32NumberFormatter(formatter).positiveFormat =
            (NSString *)formatString;
}

CFStringRef CFNumberFormatterCreateStringWithNumber(
        CFAllocatorRef allocator, CFNumberFormatterRef formatter,
        CFNumberRef number) {
    (void)allocator;
    if(!formatter || !number) return NULL;
    return (CFStringRef)[[LC32NumberFormatter(formatter)
        stringFromNumber:(NSNumber *)number] copy];
}

CFStringRef CFNumberFormatterCreateStringWithValue(
        CFAllocatorRef allocator, CFNumberFormatterRef formatter,
        CFNumberType numberType, const void *value) {
    if(!formatter || !value) return NULL;
    CFNumberRef number = CFNumberCreate(allocator, numberType, value);
    if(!number) return NULL;
    CFStringRef string = CFNumberFormatterCreateStringWithNumber(
        allocator, formatter, number);
    CFRelease(number);
    return string;
}

CFNumberRef CFNumberFormatterCreateNumberFromString(
        CFAllocatorRef allocator, CFNumberFormatterRef formatter,
        CFStringRef string, CFRange *range, CFOptionFlags options) {
    (void)allocator;
    (void)options;
    if(!formatter || !string) return NULL;

    NSString *source = (NSString *)string;
    NSRange parseRange = NSMakeRange(0, source.length);
    if(range) {
        if(range->location < 0 || range->length < 0 ||
           (NSUInteger)range->location > source.length ||
           (NSUInteger)range->length > source.length -
               (NSUInteger)range->location) {
            return NULL;
        }
        parseRange = NSMakeRange((NSUInteger)range->location,
                                 (NSUInteger)range->length);
    }

    NSNumber *number = [LC32NumberFormatter(formatter)
        numberFromString:[source substringWithRange:parseRange]];
    if(number && range) {
        range->location = (CFIndex)parseRange.location;
        range->length = (CFIndex)parseRange.length;
    }
    return (CFNumberRef)[number copy];
}

Boolean CFNumberFormatterGetValueFromString(
        CFNumberFormatterRef formatter, CFStringRef string,
        CFRange *range, CFNumberType numberType, void *value) {
    if(!value) return false;
    CFNumberRef number = CFNumberFormatterCreateNumberFromString(
        kCFAllocatorDefault, formatter, string, range, 0);
    if(!number) return false;
    const Boolean success = CFNumberGetValue(number, numberType, value);
    CFRelease(number);
    return success;
}

#define LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(KEY, GETTER, SETTER) \
    if(CFEqual(propertyName, KEY)) { \
        [nativeFormatter SETTER:(id)value]; \
        return; \
    }
#define LC32_CF_NUMBER_FORMATTER_BOOL_PROPERTY(KEY, GETTER, SETTER) \
    if(CFEqual(propertyName, KEY)) { \
        [nativeFormatter SETTER:[(NSNumber *)value boolValue]]; \
        return; \
    }
#define LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(KEY, GETTER, SETTER) \
    if(CFEqual(propertyName, KEY)) { \
        [nativeFormatter SETTER:[(NSNumber *)value unsignedIntegerValue]]; \
        return; \
    }

void CFNumberFormatterSetProperty(CFNumberFormatterRef formatter,
                                  CFNumberFormatterKey propertyName,
                                  CFTypeRef value) {
    if(!formatter || !propertyName || !value) return;
    NSNumberFormatter *nativeFormatter = LC32NumberFormatter(formatter);

    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencyCode, currencyCode, setCurrencyCode)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterDecimalSeparator, decimalSeparator,
        setDecimalSeparator)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencyDecimalSeparator,
        currencyDecimalSeparator, setCurrencyDecimalSeparator)
    LC32_CF_NUMBER_FORMATTER_BOOL_PROPERTY(
        kCFNumberFormatterAlwaysShowDecimalSeparator,
        alwaysShowsDecimalSeparator, setAlwaysShowsDecimalSeparator)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterGroupingSeparator, groupingSeparator,
        setGroupingSeparator)
    LC32_CF_NUMBER_FORMATTER_BOOL_PROPERTY(
        kCFNumberFormatterUseGroupingSeparator, usesGroupingSeparator,
        setUsesGroupingSeparator)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterPercentSymbol, percentSymbol, setPercentSymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterZeroSymbol, zeroSymbol, setZeroSymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterNaNSymbol, notANumberSymbol, setNotANumberSymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterInfinitySymbol, positiveInfinitySymbol,
        setPositiveInfinitySymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterMinusSign, minusSign, setMinusSign)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterPlusSign, plusSign, setPlusSign)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencySymbol, currencySymbol, setCurrencySymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterExponentSymbol, exponentSymbol, setExponentSymbol)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterMinIntegerDigits, minimumIntegerDigits,
        setMinimumIntegerDigits)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterMaxIntegerDigits, maximumIntegerDigits,
        setMaximumIntegerDigits)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterMinFractionDigits, minimumFractionDigits,
        setMinimumFractionDigits)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterMaxFractionDigits, maximumFractionDigits,
        setMaximumFractionDigits)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterGroupingSize, groupingSize, setGroupingSize)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterSecondaryGroupingSize, secondaryGroupingSize,
        setSecondaryGroupingSize)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterRoundingMode, roundingMode, setRoundingMode)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterRoundingIncrement, roundingIncrement,
        setRoundingIncrement)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterFormatWidth, formatWidth, setFormatWidth)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterPaddingPosition, paddingPosition,
        setPaddingPosition)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterPaddingCharacter, paddingCharacter,
        setPaddingCharacter)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterDefaultFormat, positiveFormat, setPositiveFormat)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterMultiplier, multiplier, setMultiplier)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterPositivePrefix, positivePrefix, setPositivePrefix)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterPositiveSuffix, positiveSuffix, setPositiveSuffix)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterNegativePrefix, negativePrefix, setNegativePrefix)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterNegativeSuffix, negativeSuffix, setNegativeSuffix)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterPerMillSymbol, perMillSymbol, setPerMillSymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterInternationalCurrencySymbol,
        internationalCurrencySymbol, setInternationalCurrencySymbol)
    LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencyGroupingSeparator,
        currencyGroupingSeparator, setCurrencyGroupingSeparator)
    LC32_CF_NUMBER_FORMATTER_BOOL_PROPERTY(
        kCFNumberFormatterIsLenient, isLenient, setLenient)
    LC32_CF_NUMBER_FORMATTER_BOOL_PROPERTY(
        kCFNumberFormatterUseSignificantDigits, usesSignificantDigits,
        setUsesSignificantDigits)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterMinSignificantDigits, minimumSignificantDigits,
        setMinimumSignificantDigits)
    LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY(
        kCFNumberFormatterMaxSignificantDigits, maximumSignificantDigits,
        setMaximumSignificantDigits)
}

#undef LC32_CF_NUMBER_FORMATTER_OBJECT_PROPERTY
#undef LC32_CF_NUMBER_FORMATTER_BOOL_PROPERTY
#undef LC32_CF_NUMBER_FORMATTER_UINT_PROPERTY

#define LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(KEY, GETTER) \
    if(CFEqual(propertyName, KEY)) \
        return (CFTypeRef)[[nativeFormatter GETTER] copy];
#define LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(KEY, GETTER) \
    if(CFEqual(propertyName, KEY)) \
        return (CFTypeRef)[@([nativeFormatter GETTER]) retain];

CFTypeRef CFNumberFormatterCopyProperty(
        CFNumberFormatterRef formatter,
        CFNumberFormatterKey propertyName) {
    if(!formatter || !propertyName) return NULL;
    NSNumberFormatter *nativeFormatter = LC32NumberFormatter(formatter);

    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencyCode, currencyCode)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterDecimalSeparator, decimalSeparator)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencyDecimalSeparator,
        currencyDecimalSeparator)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterAlwaysShowDecimalSeparator,
        alwaysShowsDecimalSeparator)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterGroupingSeparator, groupingSeparator)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterUseGroupingSeparator, usesGroupingSeparator)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterPercentSymbol, percentSymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterZeroSymbol, zeroSymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterNaNSymbol, notANumberSymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterInfinitySymbol, positiveInfinitySymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterMinusSign, minusSign)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterPlusSign, plusSign)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencySymbol, currencySymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterExponentSymbol, exponentSymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterMinIntegerDigits, minimumIntegerDigits)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterMaxIntegerDigits, maximumIntegerDigits)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterMinFractionDigits, minimumFractionDigits)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterMaxFractionDigits, maximumFractionDigits)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterGroupingSize, groupingSize)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterSecondaryGroupingSize, secondaryGroupingSize)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterRoundingMode, roundingMode)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterRoundingIncrement, roundingIncrement)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterFormatWidth, formatWidth)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterPaddingPosition, paddingPosition)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterPaddingCharacter, paddingCharacter)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterDefaultFormat, positiveFormat)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterMultiplier, multiplier)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterPositivePrefix, positivePrefix)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterPositiveSuffix, positiveSuffix)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterNegativePrefix, negativePrefix)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterNegativeSuffix, negativeSuffix)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterPerMillSymbol, perMillSymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterInternationalCurrencySymbol,
        internationalCurrencySymbol)
    LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY(
        kCFNumberFormatterCurrencyGroupingSeparator,
        currencyGroupingSeparator)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterIsLenient, isLenient)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterUseSignificantDigits, usesSignificantDigits)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterMinSignificantDigits, minimumSignificantDigits)
    LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY(
        kCFNumberFormatterMaxSignificantDigits, maximumSignificantDigits)
    return NULL;
}

#undef LC32_CF_NUMBER_FORMATTER_COPY_OBJECT_PROPERTY
#undef LC32_CF_NUMBER_FORMATTER_COPY_UINT_PROPERTY
