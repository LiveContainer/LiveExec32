#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static CFNumberRef LC32CMNumber(
        CFAllocatorRef allocator, CFNumberType type, const void *value) {
    return CFNumberCreate(allocator, type, value);
}

CFDictionaryRef CMTimeCopyAsDictionary(
        CMTime time, CFAllocatorRef allocator) {
    int64_t value = time.value;
    int32_t timescale = time.timescale;
    int64_t epoch = time.epoch;
    int32_t flags = (int32_t)time.flags;
    CFNumberRef values[] = {
        LC32CMNumber(allocator, kCFNumberSInt64Type, &value),
        LC32CMNumber(allocator, kCFNumberSInt32Type, &timescale),
        LC32CMNumber(allocator, kCFNumberSInt64Type, &epoch),
        LC32CMNumber(allocator, kCFNumberSInt32Type, &flags),
    };
    const void *keys[] = {
        kCMTimeValueKey, kCMTimeScaleKey, kCMTimeEpochKey, kCMTimeFlagsKey,
    };
    CFDictionaryRef result = NULL;
    if(values[0] && values[1] && values[2] && values[3]) {
        result = CFDictionaryCreate(allocator, keys,
            (const void **)values, 4, &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    }
    for(size_t index = 0; index < 4; index++) {
        if(values[index]) CFRelease(values[index]);
    }
    return result;
}

static Boolean LC32CMReadNumber(CFDictionaryRef dictionary,
        CFStringRef key, CFNumberType type, void *value) {
    if(!dictionary) return false;
    CFTypeRef number = CFDictionaryGetValue(dictionary, key);
    return number && CFGetTypeID(number) == CFNumberGetTypeID() &&
        CFNumberGetValue(number, type, value);
}

CMTime CMTimeMakeFromDictionary(CFDictionaryRef dictionary) {
    CMTime result = kCMTimeInvalid;
    int32_t flags;
    if(!LC32CMReadNumber(dictionary, kCMTimeValueKey,
            kCFNumberSInt64Type, &result.value) ||
       !LC32CMReadNumber(dictionary, kCMTimeScaleKey,
            kCFNumberSInt32Type, &result.timescale) ||
       !LC32CMReadNumber(dictionary, kCMTimeEpochKey,
            kCFNumberSInt64Type, &result.epoch) ||
       !LC32CMReadNumber(dictionary, kCMTimeFlagsKey,
            kCFNumberSInt32Type, &flags)) {
        return kCMTimeInvalid;
    }
    result.flags = (CMTimeFlags)(uint32_t)flags;
    return result;
}

CFDictionaryRef CMTimeRangeCopyAsDictionary(
        CMTimeRange range, CFAllocatorRef allocator) {
    CFDictionaryRef start = CMTimeCopyAsDictionary(range.start, allocator);
    CFDictionaryRef duration =
        CMTimeCopyAsDictionary(range.duration, allocator);
    const void *keys[] = {kCMTimeRangeStartKey, kCMTimeRangeDurationKey};
    const void *values[] = {start, duration};
    CFDictionaryRef result = NULL;
    if(start && duration) {
        result = CFDictionaryCreate(allocator, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    }
    if(start) CFRelease(start);
    if(duration) CFRelease(duration);
    return result;
}

CMTimeRange CMTimeRangeMakeFromDictionary(CFDictionaryRef dictionary) {
    if(!dictionary) return kCMTimeRangeInvalid;
    CFTypeRef start = CFDictionaryGetValue(dictionary, kCMTimeRangeStartKey);
    CFTypeRef duration =
        CFDictionaryGetValue(dictionary, kCMTimeRangeDurationKey);
    if(!start || !duration || CFGetTypeID(start) != CFDictionaryGetTypeID() ||
       CFGetTypeID(duration) != CFDictionaryGetTypeID()) {
        return kCMTimeRangeInvalid;
    }
    const CMTimeRange result = {
        CMTimeMakeFromDictionary(start),
        CMTimeMakeFromDictionary(duration),
    };
    return CMTIMERANGE_IS_VALID(result) ? result : kCMTimeRangeInvalid;
}

CFDictionaryRef CMTimeMappingCopyAsDictionary(
        CMTimeMapping mapping, CFAllocatorRef allocator) {
    CFDictionaryRef source =
        CMTimeRangeCopyAsDictionary(mapping.source, allocator);
    CFDictionaryRef target =
        CMTimeRangeCopyAsDictionary(mapping.target, allocator);
    const void *keys[] = {kCMTimeMappingSourceKey, kCMTimeMappingTargetKey};
    const void *values[] = {source, target};
    CFDictionaryRef result = NULL;
    if(source && target) {
        result = CFDictionaryCreate(allocator, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    }
    if(source) CFRelease(source);
    if(target) CFRelease(target);
    return result;
}

CMTimeMapping CMTimeMappingMakeFromDictionary(CFDictionaryRef dictionary) {
    if(!dictionary) return kCMTimeMappingInvalid;
    CFTypeRef source =
        CFDictionaryGetValue(dictionary, kCMTimeMappingSourceKey);
    CFTypeRef target =
        CFDictionaryGetValue(dictionary, kCMTimeMappingTargetKey);
    if(!source || !target || CFGetTypeID(source) != CFDictionaryGetTypeID() ||
       CFGetTypeID(target) != CFDictionaryGetTypeID()) {
        return kCMTimeMappingInvalid;
    }
    const CMTimeMapping result = {
        CMTimeRangeMakeFromDictionary(source),
        CMTimeRangeMakeFromDictionary(target),
    };
    return CMTIMEMAPPING_IS_VALID(result) ? result : kCMTimeMappingInvalid;
}

CFStringRef CMTimeCopyDescription(CFAllocatorRef allocator, CMTime time) {
    if(!CMTIME_IS_VALID(time)) {
        return CFStringCreateCopy(allocator, CFSTR("{INVALID}"));
    }
    if(CMTIME_IS_POSITIVE_INFINITY(time)) {
        return CFStringCreateCopy(allocator, CFSTR("{+infinity}"));
    }
    if(CMTIME_IS_NEGATIVE_INFINITY(time)) {
        return CFStringCreateCopy(allocator, CFSTR("{-infinity}"));
    }
    if(CMTIME_IS_INDEFINITE(time)) {
        return CFStringCreateCopy(allocator, CFSTR("{INDEFINITE}"));
    }
    if(time.epoch) {
        return CFStringCreateWithFormat(allocator, NULL,
            CMTIME_HAS_BEEN_ROUNDED(time)
                ? CFSTR("{%lld/%d = %.3f, epoch=%lld, rounded}")
                : CFSTR("{%lld/%d = %.3f, epoch=%lld}"),
            time.value, time.timescale, CMTimeGetSeconds(time), time.epoch);
    }
    return CFStringCreateWithFormat(allocator, NULL,
        CMTIME_HAS_BEEN_ROUNDED(time)
            ? CFSTR("{%lld/%d = %.3f, rounded}")
            : CFSTR("{%lld/%d = %.3f}"),
        time.value, time.timescale, CMTimeGetSeconds(time));
}

CFStringRef CMTimeRangeCopyDescription(
        CFAllocatorRef allocator, CMTimeRange range) {
    CFStringRef start = CMTimeCopyDescription(allocator, range.start);
    CFStringRef duration = CMTimeCopyDescription(allocator, range.duration);
    CFStringRef result = start && duration
        ? CFStringCreateWithFormat(allocator, NULL, CFSTR("{%@, %@}"),
            start, duration)
        : NULL;
    if(start) CFRelease(start);
    if(duration) CFRelease(duration);
    return result;
}

CFStringRef CMTimeMappingCopyDescription(
        CFAllocatorRef allocator, CMTimeMapping mapping) {
    CFStringRef source =
        CMTimeRangeCopyDescription(allocator, mapping.source);
    CFStringRef target =
        CMTimeRangeCopyDescription(allocator, mapping.target);
    CFStringRef result = source && target
        ? CFStringCreateWithFormat(allocator, NULL, CFSTR("{%@, %@}"),
            source, target)
        : NULL;
    if(source) CFRelease(source);
    if(target) CFRelease(target);
    return result;
}

void CMTimeShow(CMTime time) {
    CFStringRef description = CMTimeCopyDescription(NULL, time);
    if(description) {
        fprintf(stderr, "%s\n", [(NSString *)description UTF8String]);
        CFRelease(description);
    }
}

void CMTimeRangeShow(CMTimeRange range) {
    CFStringRef description = CMTimeRangeCopyDescription(NULL, range);
    if(description) {
        fprintf(stderr, "%s\n", [(NSString *)description UTF8String]);
        CFRelease(description);
    }
}

void CMTimeMappingShow(CMTimeMapping mapping) {
    CFStringRef description = CMTimeMappingCopyDescription(NULL, mapping);
    if(description) {
        fprintf(stderr, "%s\n", [(NSString *)description UTF8String]);
        CFRelease(description);
    }
}
