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
const CMTimeMapping kCMTimeMappingInvalid = {
    {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
    },
    {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
    },
};

typedef struct {
    uint64_t high;
    uint64_t low;
} LC32UInt128;

static uint32_t LC32GCD32(uint32_t left, uint32_t right) {
    while(right) {
        const uint32_t remainder = left % right;
        left = right;
        right = remainder;
    }
    return left;
}

static uint64_t LC32GCD64(uint64_t left, uint64_t right) {
    while(right) {
        const uint64_t remainder = left % right;
        left = right;
        right = remainder;
    }
    return left;
}

static uint64_t LC32Magnitude64(int64_t value) {
    return value < 0 ? UINT64_C(0) - (uint64_t)value : (uint64_t)value;
}

static uint32_t LC32Magnitude32(int32_t value) {
    return value < 0 ? UINT32_C(0) - (uint32_t)value : (uint32_t)value;
}

static Boolean LC32UInt128Multiply32(LC32UInt128 *value, uint32_t factor) {
    const uint64_t lowLow = (uint32_t)value->low * (uint64_t)factor;
    const uint64_t lowHigh = (value->low >> 32) * (uint64_t)factor;
    const uint64_t shiftedHigh = lowHigh << 32;
    const uint64_t resultLow = lowLow + shiftedHigh;
    const uint64_t carry = (lowHigh >> 32) + (resultLow < lowLow);
    uint64_t resultHigh;
    if(__builtin_mul_overflow(value->high, (uint64_t)factor,
            &resultHigh) ||
       __builtin_add_overflow(resultHigh, carry, &resultHigh)) {
        return false;
    }
    value->low = resultLow;
    value->high = resultHigh;
    return true;
}

static int LC32UInt128Compare(LC32UInt128 left, LC32UInt128 right) {
    if(left.high != right.high) return left.high < right.high ? -1 : 1;
    if(left.low != right.low) return left.low < right.low ? -1 : 1;
    return 0;
}

static LC32UInt128 LC32UInt128Add(
        LC32UInt128 left, LC32UInt128 right) {
    LC32UInt128 result = {left.high + right.high, left.low + right.low};
    result.high += result.low < left.low;
    return result;
}

static LC32UInt128 LC32UInt128Subtract(
        LC32UInt128 left, LC32UInt128 right) {
    LC32UInt128 result = {left.high - right.high, left.low - right.low};
    result.high -= left.low < right.low;
    return result;
}

static void LC32UInt128Divide64(LC32UInt128 numerator, uint64_t denominator,
        LC32UInt128 *quotient, uint64_t *remainder) {
    LC32UInt128 result = {0, 0};
    uint64_t rest = 0;
    for(int bit = 127; bit >= 0; bit--) {
        const uint64_t incoming = bit >= 64
            ? ((numerator.high >> (bit - 64)) & 1)
            : ((numerator.low >> bit) & 1);
        rest = (rest << 1) | incoming;
        if(rest >= denominator) {
            rest -= denominator;
            if(bit >= 64) {
                result.high |= UINT64_C(1) << (bit - 64);
            } else {
                result.low |= UINT64_C(1) << bit;
            }
        }
    }
    *quotient = result;
    *remainder = rest;
}

static Boolean LC32ShouldRoundMagnitude(uint64_t remainder,
        uint64_t denominator, Boolean negative, CMTimeRoundingMethod method,
        uint64_t oldTimescale, uint32_t newTimescale) {
    if(!remainder) return false;
    switch(method) {
        case kCMTimeRoundingMethod_RoundHalfAwayFromZero:
            return remainder >= (denominator + 1) / 2;
        case kCMTimeRoundingMethod_RoundAwayFromZero:
            return true;
        case kCMTimeRoundingMethod_QuickTime:
            return oldTimescale <= newTimescale;
        case kCMTimeRoundingMethod_RoundTowardPositiveInfinity:
            return !negative;
        case kCMTimeRoundingMethod_RoundTowardNegativeInfinity:
            return negative;
        case kCMTimeRoundingMethod_RoundTowardZero:
        default:
            return false;
    }
}

static Boolean LC32ScaleMagnitude(LC32UInt128 magnitude,
        uint32_t newTimescale, uint64_t oldTimescale, Boolean negative,
        CMTimeRoundingMethod method, int64_t *result, Boolean *rounded) {
    if(!LC32UInt128Multiply32(&magnitude, newTimescale)) return false;
    LC32UInt128 quotient;
    uint64_t remainder;
    LC32UInt128Divide64(magnitude, oldTimescale, &quotient, &remainder);
    if(LC32ShouldRoundMagnitude(remainder, oldTimescale, negative, method,
            oldTimescale, newTimescale)) {
        quotient = LC32UInt128Add(quotient, (LC32UInt128){0, 1});
    }
    const uint64_t limit = negative
        ? (UINT64_C(1) << 63) : (uint64_t)INT64_MAX;
    if(quotient.high || quotient.low > limit) return false;
    if(negative) {
        *result = quotient.low == (UINT64_C(1) << 63)
            ? INT64_MIN : -(int64_t)quotient.low;
    } else {
        *result = (int64_t)quotient.low;
    }
    *rounded = remainder != 0;
    return true;
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

static int LC32CMTimeClass(CMTime time) {
    if(!CMTIME_IS_VALID(time)) return 4;
    if(CMTIME_IS_NEGATIVE_INFINITY(time)) return 0;
    if(CMTIME_IS_NUMERIC(time)) return 1;
    if(CMTIME_IS_INDEFINITE(time)) return 2;
    if(CMTIME_IS_POSITIVE_INFINITY(time)) return 3;
    return 4;
}

static int LC32CMTimeCompare(CMTime left, CMTime right) {
    const int leftClass = LC32CMTimeClass(left);
    const int rightClass = LC32CMTimeClass(right);
    if(leftClass != rightClass) return leftClass < rightClass ? -1 : 1;
    if(leftClass != 1) return 0;
    if(left.epoch < right.epoch) return -1;
    if(left.epoch > right.epoch) return 1;
    if(left.timescale <= 0 || right.timescale <= 0) return 0;

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

static CMTime LC32CMTimeAddOrSubtract(
        CMTime left, CMTime right, Boolean subtract) {
    if(!CMTIME_IS_VALID(left) || !CMTIME_IS_VALID(right)) {
        return kCMTimeInvalid;
    }
    const Boolean rightPositiveInfinity = subtract
        ? CMTIME_IS_NEGATIVE_INFINITY(right)
        : CMTIME_IS_POSITIVE_INFINITY(right);
    const Boolean rightNegativeInfinity = subtract
        ? CMTIME_IS_POSITIVE_INFINITY(right)
        : CMTIME_IS_NEGATIVE_INFINITY(right);
    if((CMTIME_IS_POSITIVE_INFINITY(left) && rightNegativeInfinity) ||
       (CMTIME_IS_NEGATIVE_INFINITY(left) && rightPositiveInfinity)) {
        return kCMTimeInvalid;
    }
    if(CMTIME_IS_POSITIVE_INFINITY(left) || rightPositiveInfinity) {
        return kCMTimePositiveInfinity;
    }
    if(CMTIME_IS_NEGATIVE_INFINITY(left) || rightNegativeInfinity) {
        return kCMTimeNegativeInfinity;
    }
    if(CMTIME_IS_INDEFINITE(left) || CMTIME_IS_INDEFINITE(right)) {
        return kCMTimeIndefinite;
    }
    if(left.timescale <= 0 || right.timescale <= 0) return kCMTimeInvalid;
    if(left.epoch && right.epoch && left.epoch != right.epoch) {
        return kCMTimeInvalid;
    }

    const uint32_t leftScale = (uint32_t)left.timescale;
    const uint32_t rightScale = (uint32_t)right.timescale;
    const uint32_t divisor = LC32GCD32(leftScale, rightScale);
    const uint64_t commonScale =
        (uint64_t)(leftScale / divisor) * rightScale;

    LC32UInt128 leftMagnitude = {0, LC32Magnitude64(left.value)};
    LC32UInt128 rightMagnitude = {0, LC32Magnitude64(right.value)};
    LC32UInt128Multiply32(&leftMagnitude, rightScale / divisor);
    LC32UInt128Multiply32(&rightMagnitude, leftScale / divisor);
    const Boolean leftNegative = left.value < 0;
    const Boolean rightNegative = (right.value < 0) != subtract;
    LC32UInt128 magnitude;
    Boolean negative;
    if(leftNegative == rightNegative) {
        magnitude = LC32UInt128Add(leftMagnitude, rightMagnitude);
        negative = leftNegative;
    } else {
        const int comparison = LC32UInt128Compare(
            leftMagnitude, rightMagnitude);
        if(comparison >= 0) {
            magnitude = LC32UInt128Subtract(leftMagnitude, rightMagnitude);
            negative = leftNegative;
        } else {
            magnitude = LC32UInt128Subtract(rightMagnitude, leftMagnitude);
            negative = rightNegative;
        }
    }
    if(!magnitude.high && !magnitude.low) negative = false;

    uint32_t outputScale = commonScale <= INT32_MAX
        ? (uint32_t)commonScale : (uint32_t)INT32_MAX;
    for(;;) {
        int64_t value;
        Boolean rounded;
        if(LC32ScaleMagnitude(magnitude, outputScale, commonScale,
                negative, kCMTimeRoundingMethod_Default, &value, &rounded)) {
            CMTime result = {
                value,
                (int32_t)outputScale,
                kCMTimeFlags_Valid,
                left.epoch && right.epoch
                    ? 0 : (left.epoch ? left.epoch : right.epoch),
            };
            if(rounded || CMTIME_HAS_BEEN_ROUNDED(left) ||
               CMTIME_HAS_BEEN_ROUNDED(right)) {
                result.flags |= kCMTimeFlags_HasBeenRounded;
            }
            return result;
        }
        if(outputScale == 1) {
            return negative
                ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
        }
        outputScale /= 2;
        if(!outputScale) outputScale = 1;
    }
}

CMTime CMTimeMake(int64_t value, int32_t timescale) {
    if(timescale <= 0) return kCMTimeInvalid;
    const CMTime result = {
        value, timescale, kCMTimeFlags_Valid, 0,
    };
    return result;
}

CMTime CMTimeMakeWithEpoch(
        int64_t value, int32_t timescale, int64_t epoch) {
    if(timescale <= 0) return kCMTimeInvalid;
    const CMTime result = {
        value, timescale, kCMTimeFlags_Valid, epoch,
    };
    return result;
}

CMTime CMTimeMakeWithSeconds(Float64 seconds, int32_t preferredTimescale) {
    if(preferredTimescale <= 0) return kCMTimeInvalid;
    if(isinf(seconds)) {
        return seconds < 0
            ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    if(isnan(seconds)) {
        return (CMTime){
            0, preferredTimescale,
            kCMTimeFlags_Valid | kCMTimeFlags_HasBeenRounded, 0,
        };
    }
    uint32_t timescale = (uint32_t)preferredTimescale;
    for(;;) {
        const double scaled = seconds * timescale;
        if(isfinite(scaled) && scaled >= -0x1p63 && scaled < 0x1p63) {
            const int64_t value = (int64_t)scaled;
            CMTime result = {
                value, (int32_t)timescale, kCMTimeFlags_Valid, 0,
            };
            if((double)value / timescale != seconds) {
                result.flags |= kCMTimeFlags_HasBeenRounded;
            }
            return result;
        }
        if(timescale == 1) {
            return seconds < 0
                ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
        }
        timescale /= 2;
        if(!timescale) timescale = 1;
    }
}

Float64 CMTimeGetSeconds(CMTime time) {
    if(!CMTIME_IS_VALID(time) || CMTIME_IS_INDEFINITE(time) ||
       (CMTIME_IS_NUMERIC(time) && time.timescale <= 0)) return NAN;
    if(CMTIME_IS_POSITIVE_INFINITY(time)) return INFINITY;
    if(CMTIME_IS_NEGATIVE_INFINITY(time)) return -INFINITY;
    return (Float64)time.value / (Float64)time.timescale;
}

CMTime CMTimeConvertScale(CMTime time, int32_t newTimescale,
        CMTimeRoundingMethod method) {
    if(!CMTIME_IS_NUMERIC(time)) return time;
    if(time.timescale <= 0 || newTimescale <= 0) return kCMTimeInvalid;
    if(time.timescale == newTimescale) return time;
    int64_t value;
    Boolean rounded;
    const LC32UInt128 magnitude = {0, LC32Magnitude64(time.value)};
    if(!LC32ScaleMagnitude(magnitude, (uint32_t)newTimescale,
            (uint32_t)time.timescale, time.value < 0, method,
            &value, &rounded)) {
        return time.value < 0
            ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    CMTime result = {
        value, newTimescale, kCMTimeFlags_Valid, time.epoch,
    };
    if(rounded || CMTIME_HAS_BEEN_ROUNDED(time)) {
        result.flags |= kCMTimeFlags_HasBeenRounded;
    }
    return result;
}

CMTime CMTimeAdd(CMTime addend1, CMTime addend2) {
    return LC32CMTimeAddOrSubtract(addend1, addend2, false);
}

CMTime CMTimeSubtract(CMTime minuend, CMTime subtrahend) {
    return LC32CMTimeAddOrSubtract(minuend, subtrahend, true);
}

CMTime CMTimeMultiply(CMTime time, int32_t multiplier) {
    if(!CMTIME_IS_VALID(time)) return kCMTimeInvalid;
    if(CMTIME_IS_INDEFINITE(time)) return kCMTimeIndefinite;
    if(CMTIME_IS_POSITIVE_INFINITY(time) ||
       CMTIME_IS_NEGATIVE_INFINITY(time)) {
        const Boolean negative = CMTIME_IS_NEGATIVE_INFINITY(time) !=
            (multiplier < 0);
        return negative ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    if(time.timescale <= 0) return kCMTimeInvalid;
    LC32UInt128 magnitude = {0, LC32Magnitude64(time.value)};
    LC32UInt128Multiply32(&magnitude, LC32Magnitude32(multiplier));
    Boolean negative = (time.value < 0) != (multiplier < 0);
    if(!magnitude.high && !magnitude.low) negative = false;
    uint32_t outputScale = (uint32_t)time.timescale;
    for(;;) {
        int64_t value;
        Boolean rounded;
        if(LC32ScaleMagnitude(magnitude, outputScale,
                (uint32_t)time.timescale, negative,
                kCMTimeRoundingMethod_Default, &value, &rounded)) {
            CMTime result = {
                value, (int32_t)outputScale,
                kCMTimeFlags_Valid, time.epoch,
            };
            if(rounded || CMTIME_HAS_BEEN_ROUNDED(time)) {
                result.flags |= kCMTimeFlags_HasBeenRounded;
            }
            return result;
        }
        if(outputScale == 1) {
            return negative
                ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
        }
        outputScale /= 2;
        if(!outputScale) outputScale = 1;
    }
}

CMTime CMTimeMultiplyByFloat64(CMTime time, Float64 multiplier) {
    if(!CMTIME_IS_VALID(time)) return kCMTimeInvalid;
    if(CMTIME_IS_INDEFINITE(time)) return kCMTimeIndefinite;
    if(CMTIME_IS_POSITIVE_INFINITY(time) ||
       CMTIME_IS_NEGATIVE_INFINITY(time)) {
        const Boolean negative = CMTIME_IS_NEGATIVE_INFINITY(time) !=
            (multiplier < 0);
        return negative ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    if(time.timescale <= 0 || isnan(multiplier)) return kCMTimeInvalid;
    if(isinf(multiplier)) {
        if(!time.value) return kCMTimeInvalid;
        return ((time.value < 0) != (multiplier < 0))
            ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    uint32_t outputScale = (uint32_t)time.timescale;
    while(outputScale < 65536 && outputScale <= INT32_MAX / 2) {
        outputScale *= 2;
    }
    for(;;) {
        const double scaled = (double)time.value * multiplier *
            outputScale / time.timescale;
        if(isfinite(scaled) && scaled >= -0x1p63 && scaled < 0x1p63) {
            const double roundedValue = scaled < 0
                ? ceil(scaled - 0.5) : floor(scaled + 0.5);
            if(roundedValue < -0x1p63 || roundedValue >= 0x1p63) {
                if(outputScale == 1) {
                    return roundedValue < 0
                        ? kCMTimeNegativeInfinity
                        : kCMTimePositiveInfinity;
                }
                outputScale /= 2;
                if(!outputScale) outputScale = 1;
                continue;
            }
            CMTime result = {
                (int64_t)roundedValue, (int32_t)outputScale,
                kCMTimeFlags_Valid, time.epoch,
            };
            if(roundedValue != scaled || CMTIME_HAS_BEEN_ROUNDED(time)) {
                result.flags |= kCMTimeFlags_HasBeenRounded;
            }
            return result;
        }
        if(outputScale == 1) {
            return ((time.value < 0) != (multiplier < 0))
                ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
        }
        outputScale /= 2;
        if(!outputScale) outputScale = 1;
    }
}

CMTime CMTimeMultiplyByRatio(CMTime time,
        int32_t multiplier, int32_t divisor) {
    if(!CMTIME_IS_VALID(time)) return kCMTimeInvalid;
    if(CMTIME_IS_INDEFINITE(time)) return kCMTimeIndefinite;
    const Boolean inputInfinite = CMTIME_IS_POSITIVE_INFINITY(time) ||
        CMTIME_IS_NEGATIVE_INFINITY(time);
    if(divisor == 0) {
        if(multiplier == 0 || (!inputInfinite && time.value == 0)) {
            return kCMTimeInvalid;
        }
        const Boolean negative = (inputInfinite
                ? CMTIME_IS_NEGATIVE_INFINITY(time) : time.value < 0) !=
            (multiplier < 0);
        return negative ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    if(inputInfinite) {
        if(multiplier == 0) return kCMTimeInvalid;
        const Boolean negative = CMTIME_IS_NEGATIVE_INFINITY(time) !=
            (multiplier < 0) != (divisor < 0);
        return negative ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
    }
    if(time.timescale <= 0) return kCMTimeInvalid;
    LC32UInt128 magnitude = {0, LC32Magnitude64(time.value)};
    LC32UInt128Multiply32(&magnitude, LC32Magnitude32(multiplier));
    Boolean negative = (time.value < 0) != (multiplier < 0) !=
        (divisor < 0);
    if(!magnitude.high && !magnitude.low) negative = false;
    const uint64_t denominator =
        (uint64_t)(uint32_t)time.timescale * LC32Magnitude32(divisor);
    uint32_t outputScale = denominator <= INT32_MAX
        ? (uint32_t)denominator : (uint32_t)INT32_MAX;
    for(;;) {
        int64_t value;
        Boolean rounded;
        if(LC32ScaleMagnitude(magnitude, outputScale, denominator,
                negative, kCMTimeRoundingMethod_Default, &value, &rounded)) {
            CMTime result = {
                value, (int32_t)outputScale,
                kCMTimeFlags_Valid, time.epoch,
            };
            if(rounded || CMTIME_HAS_BEEN_ROUNDED(time)) {
                result.flags |= kCMTimeFlags_HasBeenRounded;
            }
            return result;
        }
        if(outputScale == 1) {
            return negative
                ? kCMTimeNegativeInfinity : kCMTimePositiveInfinity;
        }
        outputScale /= 2;
        if(!outputScale) outputScale = 1;
    }
}

int32_t CMTimeCompare(CMTime time1, CMTime time2) {
    return LC32CMTimeCompare(time1, time2);
}

CMTime CMTimeMinimum(CMTime time1, CMTime time2) {
    return LC32CMTimeCompare(time1, time2) < 0 ? time1 : time2;
}

CMTime CMTimeMaximum(CMTime time1, CMTime time2) {
    return LC32CMTimeCompare(time1, time2) >= 0 ? time1 : time2;
}

CMTime CMTimeAbsoluteValue(CMTime time) {
    if(CMTIME_IS_NEGATIVE_INFINITY(time)) return kCMTimePositiveInfinity;
    if(CMTIME_IS_NUMERIC(time) && time.value < 0 &&
       time.value != INT64_MIN) {
        time.value = -time.value;
    }
    return time;
}

CMTime CMTimeRangeGetEnd(CMTimeRange range) {
    if(!CMTIMERANGE_IS_VALID(range)) return kCMTimeInvalid;
    return CMTimeAdd(range.start, range.duration);
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

CMTimeRange CMTimeRangeMake(CMTime start, CMTime duration) {
    if(duration.epoch != 0) return kCMTimeRangeInvalid;
    return (CMTimeRange){start, duration};
}

static Boolean LC32CMTimeRangeCanCalculate(CMTimeRange range) {
    return CMTIMERANGE_IS_VALID(range) &&
        !CMTIMERANGE_IS_INDEFINITE(range);
}

CMTimeRange CMTimeRangeGetUnion(
        CMTimeRange range1, CMTimeRange range2) {
    if(!LC32CMTimeRangeCanCalculate(range1) ||
       !LC32CMTimeRangeCanCalculate(range2) ||
       range1.start.epoch != range2.start.epoch) {
        return kCMTimeRangeInvalid;
    }
    const CMTime end1 = CMTimeRangeGetEnd(range1);
    const CMTime end2 = CMTimeRangeGetEnd(range2);
    if(!CMTIME_IS_VALID(end1) || !CMTIME_IS_VALID(end2)) {
        return kCMTimeRangeInvalid;
    }
    const CMTime start = CMTimeMinimum(range1.start, range2.start);
    const CMTime end = CMTimeMaximum(end1, end2);
    return CMTimeRangeMake(start, CMTimeSubtract(end, start));
}

CMTimeRange CMTimeRangeGetIntersection(
        CMTimeRange range1, CMTimeRange range2) {
    if(!LC32CMTimeRangeCanCalculate(range1) ||
       !LC32CMTimeRangeCanCalculate(range2) ||
       range1.start.epoch != range2.start.epoch) {
        return kCMTimeRangeInvalid;
    }
    const CMTime start = CMTimeMaximum(range1.start, range2.start);
    const CMTime end = CMTimeMinimum(
        CMTimeRangeGetEnd(range1), CMTimeRangeGetEnd(range2));
    if(CMTimeCompare(end, start) <= 0) return kCMTimeRangeZero;
    return CMTimeRangeMake(start, CMTimeSubtract(end, start));
}

Boolean CMTimeRangeEqual(CMTimeRange range1, CMTimeRange range2) {
    return CMTimeCompare(range1.start, range2.start) == 0 &&
        CMTimeCompare(range1.duration, range2.duration) == 0;
}

Boolean CMTimeRangeContainsTimeRange(
        CMTimeRange range1, CMTimeRange range2) {
    if(!LC32CMTimeRangeCanCalculate(range1) ||
       !LC32CMTimeRangeCanCalculate(range2) ||
       range1.start.epoch != range2.start.epoch) {
        return false;
    }
    return CMTimeCompare(range2.start, range1.start) >= 0 &&
        CMTimeCompare(CMTimeRangeGetEnd(range2),
            CMTimeRangeGetEnd(range1)) <= 0;
}

CMTime CMTimeClampToRange(CMTime time, CMTimeRange range) {
    if(!CMTIME_IS_VALID(time) || !LC32CMTimeRangeCanCalculate(range) ||
       CMTIMERANGE_IS_EMPTY(range) || time.epoch != range.start.epoch) {
        return kCMTimeInvalid;
    }
    if(CMTimeCompare(time, range.start) < 0) return range.start;
    const CMTime end = CMTimeRangeGetEnd(range);
    if(CMTimeCompare(time, end) > 0) return end;
    return time;
}

CMTimeRange CMTimeRangeFromTimeToTime(CMTime start, CMTime end) {
    if(!CMTIME_IS_NUMERIC(start) || !CMTIME_IS_NUMERIC(end) ||
       start.epoch != end.epoch || CMTimeCompare(start, end) > 0) {
        return kCMTimeRangeInvalid;
    }
    return CMTimeRangeMake(start, CMTimeSubtract(end, start));
}

static CMTime LC32CMTimeScaleForRanges(CMTime duration,
        CMTime fromDuration, CMTime toDuration) {
    if(!CMTIME_IS_NUMERIC(duration) || duration.epoch != 0 ||
       !CMTIME_IS_NUMERIC(fromDuration) ||
       !CMTIME_IS_NUMERIC(toDuration) || fromDuration.value == 0) {
        return kCMTimeInvalid;
    }
    uint64_t numerator1 = LC32Magnitude64(toDuration.value);
    uint64_t numerator2 = (uint32_t)fromDuration.timescale;
    uint64_t denominator1 = (uint32_t)toDuration.timescale;
    uint64_t denominator2 = LC32Magnitude64(fromDuration.value);
    uint64_t divisor = LC32GCD64(numerator1, denominator1);
    numerator1 /= divisor; denominator1 /= divisor;
    divisor = LC32GCD64(numerator1, denominator2);
    numerator1 /= divisor; denominator2 /= divisor;
    divisor = LC32GCD64(numerator2, denominator1);
    numerator2 /= divisor; denominator1 /= divisor;
    divisor = LC32GCD64(numerator2, denominator2);
    numerator2 /= divisor; denominator2 /= divisor;
    uint64_t numerator;
    uint64_t denominator;
    if(!__builtin_mul_overflow(numerator1, numerator2, &numerator) &&
       !__builtin_mul_overflow(denominator1, denominator2, &denominator) &&
       numerator <= INT32_MAX && denominator <= INT32_MAX) {
        const Boolean negative = (fromDuration.value < 0) !=
            (toDuration.value < 0);
        return CMTimeMultiplyByRatio(duration,
            negative ? -(int32_t)numerator : (int32_t)numerator,
            (int32_t)denominator);
    }
    const double fromSeconds = CMTimeGetSeconds(fromDuration);
    const double toSeconds = CMTimeGetSeconds(toDuration);
    return CMTimeMultiplyByFloat64(duration, toSeconds / fromSeconds);
}

CMTime CMTimeMapDurationFromRangeToRange(CMTime duration,
        CMTimeRange fromRange, CMTimeRange toRange) {
    if(duration.epoch != 0 || !LC32CMTimeRangeCanCalculate(fromRange) ||
       !LC32CMTimeRangeCanCalculate(toRange) ||
       CMTIMERANGE_IS_EMPTY(fromRange) || CMTIMERANGE_IS_EMPTY(toRange)) {
        return kCMTimeInvalid;
    }
    if(CMTIME_IS_POSITIVE_INFINITY(fromRange.duration) &&
       CMTIME_IS_POSITIVE_INFINITY(toRange.duration)) {
        return duration;
    }
    return LC32CMTimeScaleForRanges(
        duration, fromRange.duration, toRange.duration);
}

CMTime CMTimeMapTimeFromRangeToRange(CMTime time,
        CMTimeRange fromRange, CMTimeRange toRange) {
    if(!LC32CMTimeRangeCanCalculate(fromRange) ||
       !LC32CMTimeRangeCanCalculate(toRange) ||
       CMTIMERANGE_IS_EMPTY(fromRange) || CMTIMERANGE_IS_EMPTY(toRange) ||
       !CMTIME_IS_NUMERIC(time) || time.epoch != fromRange.start.epoch) {
        return kCMTimeInvalid;
    }
    const CMTime offset = CMTimeSubtract(time, fromRange.start);
    if(CMTIME_IS_POSITIVE_INFINITY(fromRange.duration) &&
       CMTIME_IS_POSITIVE_INFINITY(toRange.duration)) {
        return CMTimeAdd(toRange.start, offset);
    }
    const CMTime mappedOffset = CMTimeMapDurationFromRangeToRange(
        offset, fromRange, toRange);
    return CMTimeAdd(toRange.start, mappedOffset);
}

CMTimeMapping CMTimeMappingMake(
        CMTimeRange source, CMTimeRange target) {
    if(source.duration.epoch != 0 || target.duration.epoch != 0) {
        return kCMTimeMappingInvalid;
    }
    return (CMTimeMapping){source, target};
}

CMTimeMapping CMTimeMappingMakeEmpty(CMTimeRange target) {
    if(target.duration.epoch != 0) return kCMTimeMappingInvalid;
    return (CMTimeMapping){kCMTimeRangeInvalid, target};
}
