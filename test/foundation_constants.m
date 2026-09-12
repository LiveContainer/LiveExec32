#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#ifndef LC32_FOUNDATION_NATIVE_CHECK
_Static_assert(sizeof(void *) == 4, "Foundation constants must work in ARM32 guests");
#endif

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL nonempty(NSString *value) {
    return value && [value isKindOfClass:[NSString class]] && [value length] != 0;
}

#define CHECK_STRING(symbol) check(#symbol, nonempty(symbol))
#define CHECK_ALIAS(ns, cf) check(#ns "-cf-alias", \
    nonempty(ns) && nonempty((NSString *)cf) && \
    [ns isEqualToString:(NSString *)cf])

static void checkCalendars(void) {
    // All 16 public iOS 10.3 calendar identifiers; 13 have public CF aliases.
    CHECK_ALIAS(NSCalendarIdentifierGregorian, kCFGregorianCalendar);
    CHECK_ALIAS(NSCalendarIdentifierBuddhist, kCFBuddhistCalendar);
    CHECK_ALIAS(NSCalendarIdentifierChinese, kCFChineseCalendar);
    CHECK_STRING(NSCalendarIdentifierCoptic);
    CHECK_STRING(NSCalendarIdentifierEthiopicAmeteMihret);
    CHECK_STRING(NSCalendarIdentifierEthiopicAmeteAlem);
    CHECK_ALIAS(NSCalendarIdentifierHebrew, kCFHebrewCalendar);
    CHECK_ALIAS(NSCalendarIdentifierISO8601, kCFISO8601Calendar);
    CHECK_ALIAS(NSCalendarIdentifierIndian, kCFIndianCalendar);
    CHECK_ALIAS(NSCalendarIdentifierIslamic, kCFIslamicCalendar);
    CHECK_ALIAS(NSCalendarIdentifierIslamicCivil, kCFIslamicCivilCalendar);
    CHECK_ALIAS(NSCalendarIdentifierJapanese, kCFJapaneseCalendar);
    CHECK_ALIAS(NSCalendarIdentifierPersian, kCFPersianCalendar);
    CHECK_ALIAS(NSCalendarIdentifierRepublicOfChina, kCFRepublicOfChinaCalendar);
    CHECK_ALIAS(NSCalendarIdentifierIslamicTabular, kCFIslamicTabularCalendar);
    CHECK_ALIAS(NSCalendarIdentifierIslamicUmmAlQura, kCFIslamicUmmAlQuraCalendar);

    CHECK_STRING(NSCalendarDayChangedNotification);
    CHECK_STRING(NSSystemClockDidChangeNotification);
    CHECK_ALIAS(NSSystemTimeZoneDidChangeNotification,
        kCFTimeZoneSystemTimeZoneDidChangeNotification);
}

static void checkTransforms(void) {
    CHECK_STRING(NSStringTransformLatinToKatakana);
    CHECK_STRING(NSStringTransformLatinToHiragana);
    CHECK_STRING(NSStringTransformLatinToHangul);
    CHECK_STRING(NSStringTransformLatinToArabic);
    CHECK_STRING(NSStringTransformLatinToHebrew);
    CHECK_STRING(NSStringTransformLatinToThai);
    CHECK_STRING(NSStringTransformLatinToCyrillic);
    CHECK_STRING(NSStringTransformLatinToGreek);
    CHECK_STRING(NSStringTransformToLatin);
    CHECK_STRING(NSStringTransformMandarinToLatin);
    CHECK_STRING(NSStringTransformHiraganaToKatakana);
    CHECK_STRING(NSStringTransformFullwidthToHalfwidth);
    CHECK_STRING(NSStringTransformToXMLHex);
    CHECK_STRING(NSStringTransformToUnicodeName);
    CHECK_STRING(NSStringTransformStripCombiningMarks);
    CHECK_STRING(NSStringTransformStripDiacritics);

    // This two-argument method is emitted by the captured NSString shim.
    // Do not assume NSString and CFString transform token payloads match.
    NSString *result = NSStringTransformStripCombiningMarks
        ? [@"Crème" stringByApplyingTransform:NSStringTransformStripCombiningMarks
                                      reverse:NO] : nil;
    check("foundation-string-transform", [result isEqualToString:@"Creme"]);
}

static void checkURLConstants(void) {
    // Representative resource keys, type values, volume properties and
    // ubiquity tokens: these reads do not access files or start cloud work.
    CHECK_ALIAS(NSURLNameKey, kCFURLNameKey);
    CHECK_ALIAS(NSURLFileSizeKey, kCFURLFileSizeKey);
    CHECK_ALIAS(NSURLFileAllocatedSizeKey, kCFURLFileAllocatedSizeKey);
    CHECK_ALIAS(NSURLIsRegularFileKey, kCFURLIsRegularFileKey);
    CHECK_ALIAS(NSURLCreationDateKey, kCFURLCreationDateKey);
    CHECK_ALIAS(NSURLFileResourceTypeKey, kCFURLFileResourceTypeKey);
    CHECK_ALIAS(NSURLFileResourceTypeRegular, kCFURLFileResourceTypeRegular);
    CHECK_ALIAS(NSURLFileResourceTypeDirectory, kCFURLFileResourceTypeDirectory);
    CHECK_ALIAS(NSURLFileResourceTypeSymbolicLink, kCFURLFileResourceTypeSymbolicLink);
    CHECK_ALIAS(NSURLVolumeTotalCapacityKey, kCFURLVolumeTotalCapacityKey);
    CHECK_ALIAS(NSURLVolumeAvailableCapacityKey, kCFURLVolumeAvailableCapacityKey);
    CHECK_ALIAS(NSURLVolumeIsReadOnlyKey, kCFURLVolumeIsReadOnlyKey);
    CHECK_ALIAS(NSURLVolumeSupportsFileCloningKey, kCFURLVolumeSupportsFileCloningKey);
    CHECK_ALIAS(NSURLIsUbiquitousItemKey, kCFURLIsUbiquitousItemKey);
    CHECK_ALIAS(NSURLUbiquitousItemDownloadingStatusKey,
        kCFURLUbiquitousItemDownloadingStatusKey);
    CHECK_ALIAS(NSURLUbiquitousItemDownloadingStatusNotDownloaded,
        kCFURLUbiquitousItemDownloadingStatusNotDownloaded);
    CHECK_ALIAS(NSURLUbiquitousItemDownloadingStatusDownloaded,
        kCFURLUbiquitousItemDownloadingStatusDownloaded);
    CHECK_ALIAS(NSURLUbiquitousItemDownloadingStatusCurrent,
        kCFURLUbiquitousItemDownloadingStatusCurrent);
    CHECK_STRING(NSURLUbiquitousItemDownloadRequestedKey);
    CHECK_STRING(NSURLThumbnailDictionaryKey);
    CHECK_STRING(NSThumbnail1024x1024SizeKey);

    if(NSURLFileSizeKey && kCFURLFileSizeKey) {
        NSDictionary *values = [NSDictionary dictionaryWithObject:@42
                                                           forKey:NSURLFileSizeKey];
        check("foundation-url-key-dictionary-interchangeability",
            [[values objectForKey:(NSString *)kCFURLFileSizeKey] intValue] == 42);
    } else {
        check("foundation-url-key-dictionary-interchangeability", NO);
    }
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    checkCalendars();
    checkTransforms();
    checkURLConstants();
    [pool drain];
    return failures != 0;
}
