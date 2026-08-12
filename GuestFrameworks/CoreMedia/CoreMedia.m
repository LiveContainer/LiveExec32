#import <CoreMedia/CoreMedia.h>

#include <limits.h>
#include <math.h>
#include <stdint.h>

/*
 * CMTime is made entirely from fixed-width integer fields, so its layout is
 * identical on the ARM32 guest and ARM64 host.  Keep the small arithmetic
 * surface used by legacy applications guest-native: this avoids a host call
 * and, more importantly, lets clang use the correct ARM32 structure-return
 * ABI for CMTime and CMTimeRange.
 */

const CMTime kCMTimeInvalid = {0, 0, 0, 0};
const CMTime kCMTimeIndefinite = {
    0, 0, kCMTimeFlags_Valid | kCMTimeFlags_Indefinite, 0,
};
const CMTime kCMTimePositiveInfinity = {
    0, 0, kCMTimeFlags_Valid | kCMTimeFlags_PositiveInfinity, 0,
};
const CMTime kCMTimeNegativeInfinity = {
    0, 0, kCMTimeFlags_Valid | kCMTimeFlags_NegativeInfinity, 0,
};
const CMTime kCMTimeZero = {0, 1, kCMTimeFlags_Valid, 0};

const CMTimeRange kCMTimeRangeZero = {
    {0, 1, kCMTimeFlags_Valid, 0},
    {0, 1, kCMTimeFlags_Valid, 0},
};
const CMTimeRange kCMTimeRangeInvalid = {
    {0, 0, 0, 0},
    {0, 0, 0, 0},
};

static uint32_t LC32GCD32(uint32_t left, uint32_t right) {
    while(right) {
        const uint32_t remainder = left % right;
        left = right;
        right = remainder;
    }
    return left;
}

static int LC32CompareUnsignedRational(uint64_t leftNumerator,
                                       uint64_t leftDenominator,
                                       uint64_t rightNumerator,
                                       uint64_t rightDenominator) {
    int direction = 1;
    for(;;) {
        const uint64_t leftQuotient =
            leftNumerator / leftDenominator;
        const uint64_t rightQuotient =
            rightNumerator / rightDenominator;
        if(leftQuotient != rightQuotient) {
            return (leftQuotient < rightQuotient ? -1 : 1) * direction;
        }

        const uint64_t leftRemainder =
            leftNumerator % leftDenominator;
        const uint64_t rightRemainder =
            rightNumerator % rightDenominator;
        if(!leftRemainder || !rightRemainder) {
            if(!leftRemainder && !rightRemainder) return 0;
            return (!leftRemainder ? -1 : 1) * direction;
        }

        leftNumerator = leftDenominator;
        leftDenominator = leftRemainder;
        rightNumerator = rightDenominator;
        rightDenominator = rightRemainder;
        direction = -direction;
    }
}

static int LC32CMTimeCompare(CMTime left, CMTime right) {
    if(!CMTIME_IS_VALID(left) || !CMTIME_IS_VALID(right)) return 0;
    if(left.epoch < right.epoch) return -1;
    if(left.epoch > right.epoch) return 1;

    if(CMTIME_IS_POSITIVE_INFINITY(left)) {
        return CMTIME_IS_POSITIVE_INFINITY(right) ? 0 : 1;
    }
    if(CMTIME_IS_NEGATIVE_INFINITY(left)) {
        return CMTIME_IS_NEGATIVE_INFINITY(right) ? 0 : -1;
    }
    if(CMTIME_IS_POSITIVE_INFINITY(right)) return -1;
    if(CMTIME_IS_NEGATIVE_INFINITY(right)) return 1;
    if(!CMTIME_IS_NUMERIC(left) || !CMTIME_IS_NUMERIC(right) ||
       left.timescale <= 0 || right.timescale <= 0) return 0;

    if(left.value < 0 && right.value >= 0) return -1;
    if(left.value >= 0 && right.value < 0) return 1;
    const uint64_t leftMagnitude = left.value < 0
        ? UINT64_C(0) - (uint64_t)left.value
        : (uint64_t)left.value;
    const uint64_t rightMagnitude = right.value < 0
        ? UINT64_C(0) - (uint64_t)right.value
        : (uint64_t)right.value;
    const int magnitudeComparison = LC32CompareUnsignedRational(
        leftMagnitude, (uint32_t)left.timescale,
        rightMagnitude, (uint32_t)right.timescale);
    return left.value < 0 ? -magnitudeComparison : magnitudeComparison;
}

static CMTime LC32CMTimeAdd(CMTime left, CMTime right) {
    if(!CMTIME_IS_VALID(left) || !CMTIME_IS_VALID(right)) {
        return kCMTimeInvalid;
    }
    if(CMTIME_IS_INDEFINITE(left) || CMTIME_IS_INDEFINITE(right)) {
        return kCMTimeIndefinite;
    }
    if((CMTIME_IS_POSITIVE_INFINITY(left) &&
            CMTIME_IS_NEGATIVE_INFINITY(right)) ||
       (CMTIME_IS_NEGATIVE_INFINITY(left) &&
            CMTIME_IS_POSITIVE_INFINITY(right))) {
        return kCMTimeInvalid;
    }
    if(CMTIME_IS_POSITIVE_INFINITY(left) ||
       CMTIME_IS_POSITIVE_INFINITY(right)) return kCMTimePositiveInfinity;
    if(CMTIME_IS_NEGATIVE_INFINITY(left) ||
       CMTIME_IS_NEGATIVE_INFINITY(right)) return kCMTimeNegativeInfinity;
    if(left.timescale <= 0 || right.timescale <= 0) return kCMTimeInvalid;

    const uint32_t leftScale = (uint32_t)left.timescale;
    const uint32_t rightScale = (uint32_t)right.timescale;
    const uint32_t divisor = LC32GCD32(leftScale, rightScale);
    const uint64_t commonScale =
        (uint64_t)(leftScale / divisor) * rightScale;
    CMTime result = kCMTimeInvalid;
    int64_t leftValue = 0;
    int64_t rightValue = 0;
    int64_t combinedValue = 0;
    if(commonScale <= INT32_MAX &&
       !__builtin_mul_overflow(left.value,
            (int64_t)(rightScale / divisor), &leftValue) &&
       !__builtin_mul_overflow(right.value,
            (int64_t)(leftScale / divisor), &rightValue) &&
       !__builtin_add_overflow(leftValue, rightValue, &combinedValue)) {
        result.value = combinedValue;
        result.timescale = (int32_t)commonScale;
        result.flags = kCMTimeFlags_Valid;
    } else {
        const int32_t outputScale =
            left.timescale > right.timescale
                ? left.timescale : right.timescale;
        const long double seconds =
            (long double)left.value / left.timescale +
            (long double)right.value / right.timescale;
        const long double scaled = seconds * outputScale;
        if(!isfinite((double)scaled) ||
           scaled < (long double)INT64_MIN ||
           scaled > (long double)INT64_MAX) {
            return scaled < 0
                ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
        }
        result.value = (int64_t)(scaled < 0 ? scaled - 0.5L : scaled + 0.5L);
        result.timescale = outputScale;
        result.flags =
            kCMTimeFlags_Valid | kCMTimeFlags_HasBeenRounded;
    }
    result.flags |= (left.flags | right.flags) &
        kCMTimeFlags_HasBeenRounded;
    result.epoch = left.epoch;
    return result;
}

CMTime CMTimeMake(int64_t value, int32_t timescale) {
    if(timescale <= 0) return kCMTimeInvalid;
    const CMTime result = {
        value, timescale, kCMTimeFlags_Valid, 0,
    };
    return result;
}

Float64 CMTimeGetSeconds(CMTime time) {
    if(!CMTIME_IS_VALID(time) || CMTIME_IS_INDEFINITE(time) ||
       (CMTIME_IS_NUMERIC(time) && time.timescale <= 0)) return NAN;
    if(CMTIME_IS_POSITIVE_INFINITY(time)) return INFINITY;
    if(CMTIME_IS_NEGATIVE_INFINITY(time)) return -INFINITY;
    return (Float64)time.value / (Float64)time.timescale;
}

CMTime CMTimeRangeGetEnd(CMTimeRange range) {
    if(!CMTIMERANGE_IS_VALID(range)) return kCMTimeInvalid;
    return LC32CMTimeAdd(range.start, range.duration);
}

Boolean CMTimeRangeContainsTime(CMTimeRange range, CMTime time) {
    if(!CMTIMERANGE_IS_VALID(range) || !CMTIME_IS_VALID(time) ||
       CMTIME_IS_INDEFINITE(range.start) ||
       CMTIME_IS_INDEFINITE(range.duration) ||
       CMTIME_IS_INDEFINITE(time) || time.epoch != range.start.epoch) {
        return false;
    }
    const CMTime end = CMTimeRangeGetEnd(range);
    if(!CMTIME_IS_VALID(end)) return false;
    return LC32CMTimeCompare(time, range.start) >= 0 &&
        LC32CMTimeCompare(time, end) < 0;
}
