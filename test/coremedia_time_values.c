#include <CoreMedia/CoreMedia.h>

#include <limits.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void check(const char *name, Boolean condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static Boolean timeBitsEqual(CMTime left, CMTime right) {
    return left.value == right.value && left.timescale == right.timescale &&
        left.flags == right.flags && left.epoch == right.epoch;
}

static Boolean rangeBitsEqual(CMTimeRange left, CMTimeRange right) {
    return timeBitsEqual(left.start, right.start) &&
        timeBitsEqual(left.duration, right.duration);
}

int main(void) {
    check("make-rejects-zero-timescale",
        timeBitsEqual(CMTimeMake(3, 0), kCMTimeInvalid));
    check("make-rejects-negative-timescale",
        timeBitsEqual(CMTimeMake(3, -1), kCMTimeInvalid));
    check("make-with-epoch", timeBitsEqual(CMTimeMakeWithEpoch(3, 2, 7),
        (CMTime){3, 2, kCMTimeFlags_Valid, 7}));

    const CMTime nanTime = CMTimeMakeWithSeconds(NAN, 600);
    check("seconds-nan-matches-coremedia",
        nanTime.value == 0 && nanTime.timescale == 600 &&
        nanTime.flags ==
            (kCMTimeFlags_Valid | kCMTimeFlags_HasBeenRounded));
    check("seconds-infinities",
        CMTIME_IS_POSITIVE_INFINITY(CMTimeMakeWithSeconds(INFINITY, 600)) &&
        CMTIME_IS_NEGATIVE_INFINITY(CMTimeMakeWithSeconds(-INFINITY, 600)));
    check("seconds-truncates-and-marks-rounded",
        timeBitsEqual(CMTimeMakeWithSeconds(0.6, 1),
            (CMTime){0, 1,
                kCMTimeFlags_Valid | kCMTimeFlags_HasBeenRounded, 0}));

    const CMTime positive = CMTimeMakeWithEpoch(5, 3, 7);
    const CMTime negative = CMTimeMakeWithEpoch(-5, 3, 7);
    check("convert-rounding-directions",
        CMTimeConvertScale(positive, 2,
            kCMTimeRoundingMethod_RoundTowardPositiveInfinity).value == 4 &&
        CMTimeConvertScale(negative, 2,
            kCMTimeRoundingMethod_RoundTowardNegativeInfinity).value == -4 &&
        CMTimeConvertScale(positive, 2,
            kCMTimeRoundingMethod_RoundTowardZero).value == 3);
    check("convert-preserves-epoch",
        CMTimeConvertScale(positive, 2,
            kCMTimeRoundingMethod_Default).epoch == 7);

    const CMTime duration = CMTimeMake(3, 2);
    const CMTime epoch7 = CMTimeMakeWithEpoch(5, 2, 7);
    const CMTime epoch7b = CMTimeMakeWithEpoch(7, 2, 7);
    const CMTime epoch8 = CMTimeMakeWithEpoch(5, 2, 8);
    check("add-duration-to-epoch",
        CMTimeAdd(duration, epoch7).epoch == 7 &&
        CMTimeSubtract(duration, epoch7).epoch == 7);
    check("same-nonzero-epochs-produce-duration",
        CMTimeAdd(epoch7, epoch7b).epoch == 0 &&
        CMTimeSubtract(epoch7b, epoch7).epoch == 0);
    check("different-nonzero-epochs-invalid",
        !CMTIME_IS_VALID(CMTimeAdd(epoch7, epoch8)) &&
        !CMTIME_IS_VALID(CMTimeSubtract(epoch7, epoch8)));
    check("exact-rational-addition",
        timeBitsEqual(CMTimeAdd(CMTimeMake(1, 3), CMTimeMake(1, 5)),
            CMTimeMake(8, 15)));

    check("multiply-infinity-by-integer-zero",
        CMTIME_IS_POSITIVE_INFINITY(
            CMTimeMultiply(kCMTimePositiveInfinity, 0)));
    check("float-zero-times-infinity-invalid",
        !CMTIME_IS_VALID(CMTimeMultiplyByFloat64(kCMTimeZero, INFINITY)));
    check("ratio-infinity-times-zero-invalid",
        !CMTIME_IS_VALID(
            CMTimeMultiplyByRatio(kCMTimePositiveInfinity, 0, 3)));
    check("ratio-zero-divisor-infinity",
        CMTIME_IS_POSITIVE_INFINITY(
            CMTimeMultiplyByRatio(CMTimeMake(5, 3), 2, 0)));
    check("absolute-int64-min-matches-coremedia",
        CMTimeAbsoluteValue(CMTimeMake(INT64_MIN, 3)).value == INT64_MIN);
    check("special-value-ordering",
        CMTimeCompare(kCMTimeNegativeInfinity, CMTimeMake(-1, 1)) < 0 &&
        CMTimeCompare(CMTimeMake(1, 1), kCMTimeIndefinite) < 0 &&
        CMTimeCompare(kCMTimeIndefinite, kCMTimePositiveInfinity) < 0 &&
        CMTimeCompare(kCMTimePositiveInfinity, kCMTimeInvalid) < 0);

    const CMTimeRange range =
        CMTimeRangeMake(CMTimeMake(2, 1), CMTimeMake(4, 1));
    const CMTimeRange disjoint =
        CMTimeRangeMake(CMTimeMake(8, 1), CMTimeMake(1, 1));
    check("range-end-exclusive",
        CMTimeRangeContainsTime(range, CMTimeMake(5, 1)) &&
        !CMTimeRangeContainsTime(range, CMTimeMake(6, 1)));
    check("range-rejects-epoch-mismatch",
        !CMTimeRangeContainsTime(range, CMTimeMakeWithEpoch(3, 1, 1)));
    check("disjoint-intersection-is-canonical-zero",
        rangeBitsEqual(CMTimeRangeGetIntersection(range, disjoint),
            kCMTimeRangeZero));
    check("range-union-and-clamp",
        timeBitsEqual(CMTimeRangeGetEnd(
            CMTimeRangeGetUnion(range, disjoint)), CMTimeMake(9, 1)) &&
        timeBitsEqual(CMTimeClampToRange(CMTimeMake(7, 1), range),
            CMTimeMake(6, 1)));

    const CMTimeRange target =
        CMTimeRangeMake(CMTimeMake(10, 1), CMTimeMake(8, 1));
    check("range-linear-mapping",
        CMTimeCompare(CMTimeMapTimeFromRangeToRange(
            CMTimeMake(3, 1), range, target), CMTimeMake(12, 1)) == 0 &&
        CMTimeCompare(CMTimeMapDurationFromRangeToRange(
            CMTimeMake(1, 1), range, target), CMTimeMake(2, 1)) == 0);
    const CMTimeMapping mapping = CMTimeMappingMake(range, target);
    check("mapping-make", CMTIMEMAPPING_IS_VALID(mapping) &&
        CMTIMEMAPPING_IS_EMPTY(CMTimeMappingMakeEmpty(target)));

    CFDictionaryRef timeDictionary =
        CMTimeCopyAsDictionary(epoch7, kCFAllocatorDefault);
    CFDictionaryRef rangeDictionary =
        CMTimeRangeCopyAsDictionary(range, kCFAllocatorDefault);
    CFDictionaryRef mappingDictionary =
        CMTimeMappingCopyAsDictionary(mapping, kCFAllocatorDefault);
    check("dictionary-roundtrips",
        timeDictionary && rangeDictionary && mappingDictionary &&
        timeBitsEqual(CMTimeMakeFromDictionary(timeDictionary), epoch7) &&
        CMTimeRangeEqual(
            CMTimeRangeMakeFromDictionary(rangeDictionary), range) &&
        CMTIMEMAPPING_IS_VALID(
            CMTimeMappingMakeFromDictionary(mappingDictionary)));
    CFStringRef description =
        CMTimeMappingCopyDescription(kCFAllocatorDefault, mapping);
    check("description-helper",
        description && CFStringGetLength(description) != 0);
    if(description) CFRelease(description);
    if(mappingDictionary) CFRelease(mappingDictionary);
    if(rangeDictionary) CFRelease(rangeDictionary);
    if(timeDictionary) CFRelease(timeDictionary);
    return failures != 0;
}
