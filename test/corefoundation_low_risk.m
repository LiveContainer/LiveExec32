#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int Check(Boolean condition, int failure) {
    return condition ? 0 : failure;
}

int main(void) {
    @autoreleasepool {
        int failed = 0;

        CFURLRef home = CFCopyHomeDirectoryURL();
        failed |= Check(home && CFURLHasDirectoryPath(home), 1);
        if(home) CFRelease(home);

        CFTimeZoneRef gmt = CFTimeZoneCreateWithTimeIntervalFromGMT(
            kCFAllocatorDefault, 0.0);
        failed |= Check(gmt &&
                        CFAbsoluteTimeGetDayOfWeek(0.0, gmt) == 1 &&
                        CFAbsoluteTimeGetDayOfYear(0.0, gmt) == 1 &&
                        CFAbsoluteTimeGetWeekOfYear(0.0, gmt) == 1, 16384);
        if(gmt) CFRelease(gmt);

        const CFRange madeRange = __CFRangeMake(3, 4);
        failed |= Check(madeRange.location == 3 && madeRange.length == 4,
                        32768);

        const UInt8 bitBytes[] = {0xa0}; /* 1, 0, 1, 0 */
        CFBitVectorRef bits = CFBitVectorCreate(
            kCFAllocatorDefault, bitBytes, 4);
        UInt8 copiedBits = 0;
        if(bits) CFBitVectorGetBits(bits, CFRangeMake(0, 4), &copiedBits);
        CFBitVectorRef bitsCopy = bits ? CFBitVectorCreateCopy(
            kCFAllocatorDefault, bits) : NULL;
        failed |= Check(bits && bitsCopy &&
                        CFBitVectorGetCount(bits) == 4 &&
                        CFBitVectorGetCountOfBit(
                            bits, CFRangeMake(0, 4), 1) == 2 &&
                        CFBitVectorContainsBit(
                            bits, CFRangeMake(1, 2), 0) &&
                        CFBitVectorGetFirstIndexOfBit(
                            bits, CFRangeMake(0, 4), 0) == 1 &&
                        CFBitVectorGetLastIndexOfBit(
                            bits, CFRangeMake(0, 4), 1) == 2 &&
                        copiedBits == 0xa0 &&
                        CFBitVectorGetCount(bitsCopy) == 4, 65536);

        CFMutableBitVectorRef mutableBits = bits
            ? CFBitVectorCreateMutableCopy(kCFAllocatorDefault, 8, bits)
            : NULL;
        CFMutableBitVectorRef emptyBits = CFBitVectorCreateMutable(
            kCFAllocatorDefault, 8);
        if(mutableBits) {
            CFBitVectorSetCount(mutableBits, 6);
            CFBitVectorSetBits(mutableBits, CFRangeMake(4, 2), 1);
            CFBitVectorFlipBitAtIndex(mutableBits, 0);
            CFBitVectorFlipBits(mutableBits, CFRangeMake(0, 2));
        }
        if(emptyBits) {
            CFBitVectorSetCount(emptyBits, 3);
            CFBitVectorSetAllBits(emptyBits, 1);
        }
        failed |= Check(mutableBits && emptyBits &&
                        CFBitVectorGetCountOfBit(
                            mutableBits, CFRangeMake(0, 6), 1) == 5 &&
                        CFBitVectorGetCountOfBit(
                            emptyBits, CFRangeMake(0, 3), 1) == 3, 131072);
        if(emptyBits) CFRelease(emptyBits);
        if(mutableBits) CFRelease(mutableBits);
        if(bitsCopy) CFRelease(bitsCopy);
        if(bits) CFRelease(bits);

        CFFileSecurityRef fileSecurity = CFFileSecurityCreate(
            kCFAllocatorDefault);
        CFUUIDRef securityUUID = CFUUIDCreateWithBytes(
            kCFAllocatorDefault,
            0, 1, 2, 3, 4, 5, 6, 7,
            8, 9, 10, 11, 12, 13, 14, 15);
        uid_t owner = 0;
        gid_t group = 0;
        mode_t mode = 0;
        if(fileSecurity && securityUUID) {
            CFFileSecuritySetOwner(fileSecurity, 501);
            CFFileSecuritySetGroup(fileSecurity, 20);
            CFFileSecuritySetMode(fileSecurity, 0640);
            CFFileSecuritySetOwnerUUID(fileSecurity, securityUUID);
            CFFileSecuritySetGroupUUID(fileSecurity, securityUUID);
        }
        CFUUIDRef copiedOwnerUUID = NULL;
        CFUUIDRef copiedGroupUUID = NULL;
        CFFileSecurityRef copiedSecurity = fileSecurity
            ? CFFileSecurityCreateCopy(kCFAllocatorDefault, fileSecurity)
            : NULL;
        failed |= Check(fileSecurity && securityUUID && copiedSecurity &&
                        CFFileSecurityGetTypeID() != 0 &&
                        CFFileSecurityGetOwner(fileSecurity, &owner) &&
                        owner == 501 &&
                        CFFileSecurityGetGroup(fileSecurity, &group) &&
                        group == 20 &&
                        CFFileSecurityGetMode(fileSecurity, &mode) &&
                        mode == 0640 &&
                        CFFileSecurityCopyOwnerUUID(
                            fileSecurity, &copiedOwnerUUID) &&
                        CFEqual(securityUUID, copiedOwnerUUID) &&
                        CFFileSecurityCopyGroupUUID(
                            fileSecurity, &copiedGroupUUID) &&
                        CFEqual(securityUUID, copiedGroupUUID), 262144);
        if(fileSecurity) CFFileSecurityClearProperties(fileSecurity,
            kCFFileSecurityClearOwner | kCFFileSecurityClearGroup |
            kCFFileSecurityClearMode | kCFFileSecurityClearOwnerUUID |
            kCFFileSecurityClearGroupUUID);
        if(copiedGroupUUID) CFRelease(copiedGroupUUID);
        if(copiedOwnerUUID) CFRelease(copiedOwnerUUID);
        if(copiedSecurity) CFRelease(copiedSecurity);
        if(securityUUID) CFRelease(securityUUID);
        if(fileSecurity) CFRelease(fileSecurity);

        CFDateFormatterRef isoFormatter =
            CFDateFormatterCreateISO8601Formatter(
                kCFAllocatorDefault,
                kCFISO8601DateFormatWithInternetDateTime);
        int32_t fractionDigits = -1;
        double roundingIncrement = -1.0;
        failed |= Check(isoFormatter &&
                        CFNumberFormatterGetDecimalInfoForCurrencyCode(
                            CFSTR("USD"), &fractionDigits,
                            &roundingIncrement) &&
                        fractionDigits == 2 && roundingIncrement >= 0.0,
                        524288);
        if(isoFormatter) CFRelease(isoFormatter);

        static const UInt8 xml[] =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
            "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
            "<plist version=\"1.0\"><dict><key>value</key>"
            "<string>ok</string></dict></plist>";
        CFDataRef data = CFDataCreate(
            kCFAllocatorDefault, xml, sizeof(xml) - 1);
        CFStringRef propertyListError = NULL;
        CFPropertyListRef propertyList = CFPropertyListCreateFromXMLData(
            kCFAllocatorDefault, data, kCFPropertyListImmutable,
            &propertyListError);
        failed |= Check(propertyList && !propertyListError, 2);
        if(propertyList) CFRelease(propertyList);
        if(propertyListError) CFRelease(propertyListError);
        if(data) CFRelease(data);

        CFArrayRef currencies = CFLocaleCopyCommonISOCurrencyCodes();
        CFArrayRef languages = CFLocaleCopyPreferredLanguages();
        failed |= Check(currencies && CFArrayGetCount(currencies) > 0 &&
                        languages && CFArrayGetCount(languages) > 0, 4);
        if(currencies) CFRelease(currencies);
        if(languages) CFRelease(languages);

        CFLocaleIdentifier windowsLocale =
            CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode(
                kCFAllocatorDefault, 0x0409);
        CFLocaleIdentifier scriptLocale =
            CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes(
                kCFAllocatorDefault, 0, 0);
        failed |= Check(windowsLocale &&
            CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier(
                windowsLocale) == 0x0409 && scriptLocale, 8);
        if(scriptLocale) CFRelease(scriptLocale);
        if(windowsLocale) CFRelease(windowsLocale);
        failed |= Check(CFLocaleGetLanguageCharacterDirection(CFSTR("en")) ==
                            kCFLocaleLanguageDirectionLeftToRight &&
                        CFLocaleGetLanguageLineDirection(CFSTR("ar")) ==
                            kCFLocaleLanguageDirectionRightToLeft, 16);

        CFURLRef decomposableURL = CFURLCreateWithString(
            kCFAllocatorDefault,
            CFSTR("http://example.com/path;parameter?query#fragment"),
            NULL);
        CFStringRef netLocation = decomposableURL
            ? CFURLCopyNetLocation(decomposableURL) : NULL;
        CFStringRef parameter = decomposableURL
            ? CFURLCopyParameterString(decomposableURL, CFSTR("")) : NULL;
        if(decomposableURL) {
            CFURLClearResourcePropertyCache(decomposableURL);
            CFURLClearResourcePropertyCacheForKey(
                decomposableURL, CFSTR("org.liveexec32.test"));
            CFURLSetTemporaryResourcePropertyForKey(
                decomposableURL, CFSTR("org.liveexec32.test"), CFSTR("ok"));
            if(CFURLStartAccessingSecurityScopedResource(decomposableURL))
                CFURLStopAccessingSecurityScopedResource(decomposableURL);
        }
        failed |= Check(decomposableURL && netLocation && parameter &&
                        CFEqual(netLocation, CFSTR("example.com")) &&
                        CFEqual(parameter, CFSTR("parameter")) &&
                        !CFURLIsFileReferenceURL(decomposableURL), 1048576);

        CFDataRef serializedURL = decomposableURL ? CFURLCreateData(
            kCFAllocatorDefault, decomposableURL,
            kCFStringEncodingUTF8, false) : NULL;
        failed |= Check(serializedURL &&
                        CFDataGetLength(serializedURL) > 0, 2097152);
        if(serializedURL) CFRelease(serializedURL);
        if(parameter) CFRelease(parameter);
        if(netLocation) CFRelease(netLocation);
        if(decomposableURL) CFRelease(decomposableURL);

        CFURLRef resourceURL = CFCopyHomeDirectoryURL();
        const CFStringRef temporaryKey =
            CFSTR("org.liveexec32.low-risk-resource");
        CFTypeRef temporaryValue = NULL;
        CFErrorRef resourceError = NULL;
        if(resourceURL) CFURLSetTemporaryResourcePropertyForKey(
            resourceURL, temporaryKey, CFSTR("temporary-value"));
        const Boolean copiedTemporaryValue = resourceURL &&
            CFURLCopyResourcePropertyForKey(
                resourceURL, temporaryKey, &temporaryValue,
                &resourceError);
        if(resourceError) {
            CFRelease(resourceError);
            resourceError = NULL;
        }
        const void *resourceKeyValues[] = {temporaryKey};
        CFArrayRef resourceKeys = CFArrayCreate(
            kCFAllocatorDefault, resourceKeyValues, 1,
            &kCFTypeArrayCallBacks);
        CFDictionaryRef resourceProperties = resourceURL && resourceKeys
            ? CFURLCopyResourcePropertiesForKeys(
                resourceURL, resourceKeys, &resourceError)
            : NULL;
        if(resourceError) {
            CFRelease(resourceError);
            resourceError = NULL;
        }
        CFTypeRef copiedMultipleValue = resourceProperties
            ? CFDictionaryGetValue(resourceProperties, temporaryKey)
            : NULL;
        const Boolean resourceIsReachable = resourceURL &&
            CFURLResourceIsReachable(resourceURL, &resourceError);
        failed |= Check(resourceURL && copiedTemporaryValue &&
                        temporaryValue &&
                        CFEqual(temporaryValue, CFSTR("temporary-value")) &&
                        copiedMultipleValue &&
                        CFEqual(copiedMultipleValue,
                            CFSTR("temporary-value")) &&
                        resourceIsReachable, 4194304);
        if(resourceError) {
            CFRelease(resourceError);
            resourceError = NULL;
        }

        CFDictionaryRef noResourceChanges = CFDictionaryCreate(
            kCFAllocatorDefault, NULL, NULL, 0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
        if(resourceURL && noResourceChanges)
            (void)CFURLSetResourcePropertiesForKeys(
                resourceURL, noResourceChanges, NULL);
        CFURLRef filePathURL = resourceURL ? CFURLCreateFilePathURL(
            kCFAllocatorDefault, resourceURL, NULL) : NULL;
        CFURLRef fileReferenceURL = resourceURL
            ? CFURLCreateFileReferenceURL(
                kCFAllocatorDefault, resourceURL, NULL) : NULL;
        if(fileReferenceURL) CFRelease(fileReferenceURL);
        if(filePathURL) CFRelease(filePathURL);
        if(noResourceChanges) CFRelease(noResourceChanges);
        if(resourceProperties) CFRelease(resourceProperties);
        if(resourceKeys) CFRelease(resourceKeys);
        if(temporaryValue) CFRelease(temporaryValue);

        CFReadStreamRef fileReadStream = resourceURL
            ? CFReadStreamCreateWithFile(
                kCFAllocatorDefault, resourceURL) : NULL;
        CFWriteStreamRef fileWriteStream = resourceURL
            ? CFWriteStreamCreateWithFile(
                kCFAllocatorDefault, resourceURL) : NULL;
        CFWriteStreamRef memoryWriteStream =
            CFWriteStreamCreateWithAllocatedBuffers(
                kCFAllocatorDefault, kCFAllocatorDefault);
        static const UInt8 streamBytes[] = "stream-constructor";
        Boolean memoryStreamOK = memoryWriteStream &&
            CFWriteStreamOpen(memoryWriteStream) &&
            CFWriteStreamWrite(memoryWriteStream, streamBytes,
                sizeof(streamBytes) - 1) ==
                    (CFIndex)sizeof(streamBytes) - 1;
        CFDataRef writtenData = memoryWriteStream
            ? (CFDataRef)CFWriteStreamCopyProperty(
                memoryWriteStream, kCFStreamPropertyDataWritten) : NULL;
        CFReadStreamRef boundReadStream = NULL;
        CFWriteStreamRef boundWriteStream = NULL;
        CFStreamCreateBoundPair(kCFAllocatorDefault,
            &boundReadStream, &boundWriteStream, 0);
        failed |= Check(fileReadStream && fileWriteStream &&
                        memoryStreamOK && writtenData &&
                        CFDataGetLength(writtenData) ==
                            (CFIndex)sizeof(streamBytes) - 1 &&
                        boundReadStream && boundWriteStream, 8388608);
        if(boundWriteStream) CFRelease(boundWriteStream);
        if(boundReadStream) CFRelease(boundReadStream);
        if(writtenData) CFRelease(writtenData);
        if(memoryWriteStream) {
            CFWriteStreamClose(memoryWriteStream);
            CFRelease(memoryWriteStream);
        }
        if(fileWriteStream) CFRelease(fileWriteStream);
        if(fileReadStream) CFRelease(fileReadStream);
        if(resourceURL) CFRelease(resourceURL);

        CFStringRef source = CFSTR("alpha\nbeta");
        CFRange match = CFRangeMake(kCFNotFound, 0);
        failed |= Check(CFStringCompareWithOptionsAndLocale(
                            CFSTR("Alpha"), CFSTR("alpha"),
                            CFRangeMake(0, 5), kCFCompareCaseInsensitive,
                            NULL) == kCFCompareEqualTo, 32);
        failed |= Check(CFStringFindWithOptionsAndLocale(
                            source, CFSTR("BETA"),
                            CFRangeMake(0, CFStringGetLength(source)),
                            kCFCompareCaseInsensitive, NULL, &match) &&
                            match.location == 6 && match.length == 4, 64);

        CFIndex begin = -1;
        CFIndex end = -1;
        CFIndex contentsEnd = -1;
        CFStringGetLineBounds(source, CFRangeMake(0, 1),
                              &begin, &end, &contentsEnd);
        failed |= Check(begin == 0 && end == 6 && contentsEnd == 5, 128);
        CFStringGetParagraphBounds(source, CFRangeMake(6, 1),
                                   &begin, &end, &contentsEnd);
        failed |= Check(begin == 6 && end == 10 && contentsEnd == 10, 256);

        failed |= Check(CFStringGetSmallestEncoding(CFSTR("ASCII")) !=
                            kCFStringEncodingInvalidId &&
                        CFStringGetSystemEncoding() !=
                            kCFStringEncodingInvalidId &&
                        CFStringIsEncodingAvailable(
                            kCFStringEncodingASCII) &&
                        CFStringGetNameOfEncoding(
                            kCFStringEncodingASCII) != NULL, 512);
        failed |= Check(CFStringConvertEncodingToWindowsCodepage(
                            kCFStringEncodingWindowsLatin1) == 1252 &&
                        CFStringConvertWindowsCodepageToEncoding(1252) ==
                            kCFStringEncodingWindowsLatin1, 1024);

        CFMutableStringRef mutable = CFStringCreateMutableCopy(
            kCFAllocatorDefault, 0, CFSTR("ab"));
        CFStringPad(mutable, CFSTR("."), 5, 0);
        failed |= Check(CFEqual(mutable, CFSTR("ab...")), 2048);
        CFStringReplaceAll(mutable, CFSTR("xxabcxx"));
        CFStringTrim(mutable, CFSTR("xx"));
        failed |= Check(CFEqual(mutable, CFSTR("abc")), 4096);
        if(mutable) CFRelease(mutable);

        const CFTypeID typeIDs[] = {
            CFAttributedStringGetTypeID(),
            CFBitVectorGetTypeID(),
            CFBundleGetTypeID(),
            CFNotificationCenterGetTypeID(),
            CFReadStreamGetTypeID(),
            CFWriteStreamGetTypeID(),
            CFRunLoopGetTypeID(),
            CFRunLoopSourceGetTypeID(),
            CFRunLoopTimerGetTypeID(),
            CFSocketGetTypeID(),
        };
        for(size_t index = 0; index < sizeof(typeIDs) / sizeof(typeIDs[0]);
                index++) {
            if(!typeIDs[index]) failed |= 8192;
        }

        return failed != 0;
    }
}
