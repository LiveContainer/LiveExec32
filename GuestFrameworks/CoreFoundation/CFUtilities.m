#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

const CFRunLoopMode kCFRunLoopCommonModes = CFSTR("kCFRunLoopCommonModes");

typedef union {
    CFUUIDBytes bytes;
    UInt8 rawBytes[16];
} LC32CFUUIDBytes;

typedef struct LC32CFConstantUUIDEntry {
    LC32CFUUIDBytes storage;
    CFUUIDRef uuid;
    struct LC32CFConstantUUIDEntry *next;
} LC32CFConstantUUIDEntry;

static LC32CFConstantUUIDEntry *LC32CFConstantUUIDs;

_Static_assert(sizeof(CFUUIDBytes) == 16,
               "CFUUIDBytes must contain exactly 16 bytes");
_Static_assert(sizeof(LC32CFUUIDBytes) == 16,
               "LC32CFUUIDBytes must not add padding");
_Static_assert(offsetof(CFUUIDBytes, byte0) == 0,
               "CFUUIDBytes byte0 must be first");
_Static_assert(offsetof(CFUUIDBytes, byte15) == 15,
               "CFUUIDBytes byte15 must be last");

static int LC32CFUUIDHexValue(unsigned char character) {
    if(character >= '0' && character <= '9') return character - '0';
    if(character >= 'A' && character <= 'F') return character - 'A' + 10;
    if(character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

static Boolean LC32CFUUIDParseString(const char *text,
                                     UInt8 rawBytes[16]) {
    if(!text || !rawBytes) return false;
    UInt8 parsed[16];
    size_t byteIndex = 0;
    int highNibble = -1;
    for(const unsigned char *cursor = (const unsigned char *)text;
            *cursor; ++cursor) {
        if(*cursor == '-') continue;
        const int nibble = LC32CFUUIDHexValue(*cursor);
        if(nibble < 0) return false;
        if(highNibble < 0) {
            highNibble = nibble;
            continue;
        }
        if(byteIndex == sizeof(parsed)) return false;
        parsed[byteIndex++] = (UInt8)((highNibble << 4) | nibble);
        highNibble = -1;
    }
    if(byteIndex != sizeof(parsed) || highNibble >= 0) return false;
    memcpy(rawBytes, parsed, sizeof(parsed));
    return true;
}

static LC32CFUUIDBytes LC32CFUUIDBytesMake(
        UInt8 byte0, UInt8 byte1, UInt8 byte2, UInt8 byte3,
        UInt8 byte4, UInt8 byte5, UInt8 byte6, UInt8 byte7,
        UInt8 byte8, UInt8 byte9, UInt8 byte10, UInt8 byte11,
        UInt8 byte12, UInt8 byte13, UInt8 byte14, UInt8 byte15) {
    const LC32CFUUIDBytes storage = {.bytes = {
        byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7,
        byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15,
    }};
    return storage;
}

/* Foundation's iOS 6 import is two-level bound to CoreFoundation. */
NSString * const NSGregorianCalendar = @"gregorian";

CFAbsoluteTime CFAbsoluteTimeGetCurrent(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

CFBundleRef CFBundleGetMainBundle(void) {
    return (CFBundleRef)LC32_CF_CALL0(
        LC32CoreFoundationOpBundleGetMainBundle);
}

CFDictionaryRef CFBundleGetInfoDictionary(CFBundleRef bundle) {
    return bundle
        ? (CFDictionaryRef)[(NSBundle *)bundle infoDictionary]
        : NULL;
}

CFDictionaryRef CFBundleGetLocalInfoDictionary(CFBundleRef bundle) {
    return bundle
        ? (CFDictionaryRef)[(NSBundle *)bundle localizedInfoDictionary]
        : NULL;
}

CFTypeRef CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle,
                                                CFStringRef key) {
    if(!bundle || !key) return NULL;
    return (CFTypeRef)[(NSBundle *)bundle
        objectForInfoDictionaryKey:(NSString *)key];
}

CFStringRef CFBundleGetDevelopmentRegion(CFBundleRef bundle) {
    return bundle
        ? (CFStringRef)[(NSBundle *)bundle developmentLocalization]
        : NULL;
}

static CFURLRef LC32CFBundleCopyURL(NSURL *url) {
    return url ? (CFURLRef)[url copy] : NULL;
}

CFURLRef CFBundleCopySupportFilesDirectoryURL(CFBundleRef bundle) {
    return bundle ? LC32CFBundleCopyURL([(NSBundle *)bundle bundleURL]) : NULL;
}

CFURLRef CFBundleCopyResourcesDirectoryURL(CFBundleRef bundle) {
    return bundle ? LC32CFBundleCopyURL([(NSBundle *)bundle resourceURL]) : NULL;
}

CFURLRef CFBundleCopyPrivateFrameworksURL(CFBundleRef bundle) {
    return bundle
        ? LC32CFBundleCopyURL([(NSBundle *)bundle privateFrameworksURL]) : NULL;
}

CFURLRef CFBundleCopySharedFrameworksURL(CFBundleRef bundle) {
    return bundle
        ? LC32CFBundleCopyURL([(NSBundle *)bundle sharedFrameworksURL]) : NULL;
}

CFURLRef CFBundleCopySharedSupportURL(CFBundleRef bundle) {
    return bundle
        ? LC32CFBundleCopyURL([(NSBundle *)bundle sharedSupportURL]) : NULL;
}

CFURLRef CFBundleCopyBuiltInPlugInsURL(CFBundleRef bundle) {
    return bundle
        ? LC32CFBundleCopyURL([(NSBundle *)bundle builtInPlugInsURL]) : NULL;
}

CFURLRef CFBundleCopyExecutableURL(CFBundleRef bundle) {
    return bundle
        ? LC32CFBundleCopyURL([(NSBundle *)bundle executableURL]) : NULL;
}

CFURLRef CFBundleCopyAuxiliaryExecutableURL(CFBundleRef bundle,
                                            CFStringRef executableName) {
    if(!bundle || !executableName) return NULL;
    return LC32CFBundleCopyURL([(NSBundle *)bundle
        URLForAuxiliaryExecutable:(NSString *)executableName]);
}

CFArrayRef CFBundleCopyExecutableArchitectures(CFBundleRef bundle) {
    return bundle
        ? (CFArrayRef)[[(NSBundle *)bundle executableArchitectures] copy]
        : NULL;
}

CFArrayRef CFBundleCopyBundleLocalizations(CFBundleRef bundle) {
    return bundle ? (CFArrayRef)[[(NSBundle *)bundle localizations] copy]
                  : NULL;
}

CFArrayRef CFBundleCopyPreferredLocalizationsFromArray(
        CFArrayRef localizations) {
    return localizations ? (CFArrayRef)[[NSBundle
        preferredLocalizationsFromArray:(NSArray *)localizations] copy] : NULL;
}

CFArrayRef CFBundleCopyLocalizationsForPreferences(
        CFArrayRef localizations, CFArrayRef preferences) {
    if(!localizations || !preferences) return NULL;
    return (CFArrayRef)[[NSBundle
        preferredLocalizationsFromArray:(NSArray *)localizations
        forPreferences:(NSArray *)preferences] copy];
}

CFArrayRef CFBundleCopyResourceURLsOfType(
        CFBundleRef bundle, CFStringRef resourceType,
        CFStringRef subdirectoryName) {
    if(!bundle) return NULL;
    return (CFArrayRef)[[(NSBundle *)bundle
        URLsForResourcesWithExtension:(NSString *)resourceType
        subdirectory:(NSString *)subdirectoryName] copy];
}

CFURLRef CFBundleCopyResourceURLForLocalization(
        CFBundleRef bundle, CFStringRef resourceName, CFStringRef resourceType,
        CFStringRef subdirectoryName, CFStringRef localizationName) {
    if(!bundle || !resourceName) return NULL;
    return LC32CFBundleCopyURL([(NSBundle *)bundle
        URLForResource:(NSString *)resourceName
        withExtension:(NSString *)resourceType
        subdirectory:(NSString *)subdirectoryName
        localization:(NSString *)localizationName]);
}

CFArrayRef CFBundleCopyResourceURLsOfTypeForLocalization(
        CFBundleRef bundle, CFStringRef resourceType,
        CFStringRef subdirectoryName, CFStringRef localizationName) {
    if(!bundle) return NULL;
    return (CFArrayRef)[[(NSBundle *)bundle
        URLsForResourcesWithExtension:(NSString *)resourceType
        subdirectory:(NSString *)subdirectoryName
        localization:(NSString *)localizationName] copy];
}

Boolean CFBundlePreflightExecutable(CFBundleRef bundle, CFErrorRef *error) {
    if(!bundle) {
        if(error) *error = NULL;
        return false;
    }
    return LC32_CF_CALL(LC32CoreFoundationOpBundlePreflightExecutable,
        LC32_CF_HOST(bundle), LC32_CF_U32((uintptr_t)error));
}

Boolean CFBundleLoadExecutableAndReturnError(CFBundleRef bundle,
                                             CFErrorRef *error) {
    if(!bundle) {
        if(error) *error = NULL;
        return false;
    }
    return LC32_CF_CALL(
        LC32CoreFoundationOpBundleLoadExecutableAndReturnError,
        LC32_CF_HOST(bundle), LC32_CF_U32((uintptr_t)error));
}

Boolean CFBundleLoadExecutable(CFBundleRef bundle) {
    return bundle && [(NSBundle *)bundle load];
}

Boolean CFBundleIsExecutableLoaded(CFBundleRef bundle) {
    return bundle && [(NSBundle *)bundle isLoaded];
}

void CFBundleUnloadExecutable(CFBundleRef bundle) {
    if(bundle) [(NSBundle *)bundle unload];
}

CFStringRef CFBundleGetIdentifier(CFBundleRef bundle) {
    return bundle ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetIdentifier,
        LC32_CF_HOST(bundle)) : NULL;
}

CFURLRef CFBundleCopyBundleURL(CFBundleRef bundle) {
    return bundle ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCopyBundleURL,
        LC32_CF_HOST(bundle)) : NULL;
}

UInt32 CFBundleGetVersionNumber(CFBundleRef bundle) {
    return bundle ? LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetVersionNumber,
        LC32_CF_HOST(bundle)) : 0;
}

CFStringRef CFBundleCopyLocalizedString(
        CFBundleRef bundle, CFStringRef key, CFStringRef value,
        CFStringRef tableName) {
    if(!bundle || !key) return value ? (CFStringRef)CFRetain(value) : NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCopyLocalizedString,
        LC32_CF_HOST(bundle), LC32_CF_HOST(key), LC32_CF_HOST(value),
        LC32_CF_HOST(tableName));
}

CFURLRef CFBundleCopyResourceURL(
        CFBundleRef bundle, CFStringRef resourceName,
        CFStringRef resourceType, CFStringRef subDirName) {
    if(!bundle || !resourceName) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCopyResourceURL,
        LC32_CF_HOST(bundle), LC32_CF_HOST(resourceName),
        LC32_CF_HOST(resourceType), LC32_CF_HOST(subDirName));
}

CFBundleRef CFBundleCreate(CFAllocatorRef allocator, CFURLRef bundleURL) {
    (void)allocator;
    return bundleURL ? (CFBundleRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleCreate,
        LC32_CF_HOST(bundleURL)) : NULL;
}

CFBundleRef CFBundleGetBundleWithIdentifier(CFStringRef bundleID) {
    return bundleID ? (CFBundleRef)LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetBundleWithIdentifier,
        LC32_CF_HOST(bundleID)) : NULL;
}

void *CFBundleGetFunctionPointerForName(
        CFBundleRef bundle, CFStringRef functionName) {
    if(!bundle || !functionName) return NULL;
    return (void *)(uintptr_t)LC32_CF_CALL(
        LC32CoreFoundationOpBundleGetFunctionPointerForName,
        LC32_CF_HOST(bundle), LC32_CF_HOST(functionName));
}

CFRunLoopRef CFRunLoopGetMain(void) {
    return (CFRunLoopRef)LC32_CF_CALL0(
        LC32CoreFoundationOpRunLoopGetMain);
}

CFRunLoopRef CFRunLoopGetCurrent(void) {
    return (CFRunLoopRef)LC32_CF_CALL0(
        LC32CoreFoundationOpRunLoopGetCurrent);
}

CFTypeID CFUUIDGetTypeID(void) {
    static CFTypeID typeID;
    if(typeID) return typeID;
    @synchronized([NSUUID class]) {
        if(!typeID) {
            CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
            if(uuid) {
                typeID = CFGetTypeID(uuid);
                CFRelease(uuid);
            }
        }
    }
    return typeID;
}

CFUUIDRef CFUUIDCreate(CFAllocatorRef allocator) {
    (void)allocator;
    return (CFUUIDRef)[[NSUUID alloc] init];
}

CFUUIDRef CFUUIDCreateWithBytes(
        CFAllocatorRef allocator,
        UInt8 byte0, UInt8 byte1, UInt8 byte2, UInt8 byte3,
        UInt8 byte4, UInt8 byte5, UInt8 byte6, UInt8 byte7,
        UInt8 byte8, UInt8 byte9, UInt8 byte10, UInt8 byte11,
        UInt8 byte12, UInt8 byte13, UInt8 byte14, UInt8 byte15) {
    const LC32CFUUIDBytes storage = LC32CFUUIDBytesMake(
        byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7,
        byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15);
    return CFUUIDCreateFromUUIDBytes(allocator, storage.bytes);
}

CFUUIDRef CFUUIDCreateFromString(CFAllocatorRef allocator,
                                 CFStringRef uuidString) {
    (void)allocator;
    return uuidString ? (CFUUIDRef)[[NSUUID alloc]
        initWithUUIDString:(NSString *)uuidString] : NULL;
}

CFUUIDRef CFUUIDGetConstantUUIDWithBytes(
        CFAllocatorRef allocator,
        UInt8 byte0, UInt8 byte1, UInt8 byte2, UInt8 byte3,
        UInt8 byte4, UInt8 byte5, UInt8 byte6, UInt8 byte7,
        UInt8 byte8, UInt8 byte9, UInt8 byte10, UInt8 byte11,
        UInt8 byte12, UInt8 byte13, UInt8 byte14, UInt8 byte15) {
    const LC32CFUUIDBytes storage = LC32CFUUIDBytesMake(
        byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7,
        byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15);

    @synchronized([NSUUID class]) {
        for(LC32CFConstantUUIDEntry *entry = LC32CFConstantUUIDs;
                entry; entry = entry->next) {
            if(memcmp(entry->storage.rawBytes, storage.rawBytes,
                      sizeof(storage.rawBytes)) == 0) {
                return entry->uuid;
            }
        }

        CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(allocator,
                                                   storage.bytes);
        if(!uuid) return NULL;
        LC32CFConstantUUIDEntry *entry = malloc(sizeof(*entry));
        if(!entry) {
            /* The create retain is deliberately leaked: this API promises
             * process-lifetime identity even if caching metadata is OOM. */
            return uuid;
        }
        entry->storage = storage;
        entry->uuid = uuid;
        entry->next = LC32CFConstantUUIDs;
        LC32CFConstantUUIDs = entry;
        return uuid;
    }
}

CFUUIDRef CFUUIDCreateFromUUIDBytes(CFAllocatorRef allocator,
                                    CFUUIDBytes bytes) {
    static const char digits[] = "0123456789ABCDEF";
    const LC32CFUUIDBytes storage = {.bytes = bytes};
    char text[37];
    size_t output = 0;
    for(size_t index = 0; index < sizeof(storage.rawBytes); ++index) {
        if(index == 4 || index == 6 || index == 8 || index == 10) {
            text[output++] = '-';
        }
        text[output++] = digits[storage.rawBytes[index] >> 4];
        text[output++] = digits[storage.rawBytes[index] & 0x0f];
    }
    text[output] = '\0';

    CFStringRef string = CFStringCreateWithBytes(
        allocator, (const UInt8 *)text, (CFIndex)output,
        kCFStringEncodingASCII, false);
    if(!string) return NULL;
    CFUUIDRef uuid = (CFUUIDRef)[[NSUUID alloc]
        initWithUUIDString:(NSString *)string];
    CFRelease(string);
    return uuid;
}

CFUUIDBytes CFUUIDGetUUIDBytes(CFUUIDRef uuid) {
    LC32CFUUIDBytes result = {0};
    if(!uuid) return result.bytes;
    NSString *string = [(NSUUID *)uuid UUIDString];
    LC32CFUUIDParseString(string.UTF8String, result.rawBytes);
    return result.bytes;
}

CFStringRef CFUUIDCreateString(CFAllocatorRef allocator, CFUUIDRef uuid) {
    (void)allocator;
    return uuid ? (CFStringRef)[[(NSUUID *)uuid UUIDString] copy] : NULL;
}

CFStringRef CFURLCreateStringByAddingPercentEscapes(
        CFAllocatorRef allocator, CFStringRef originalString,
        CFStringRef charactersToLeaveUnescaped,
        CFStringRef legalURLCharactersToBeEscaped,
        CFStringEncoding encoding) {
    (void)allocator;
    if(!originalString) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateStringByAddingPercentEscapes,
        LC32_CF_HOST(originalString),
        LC32_CF_HOST(charactersToLeaveUnescaped),
        LC32_CF_HOST(legalURLCharactersToBeEscaped),
        LC32_CF_U32(encoding));
}

CFStringRef CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
        CFAllocatorRef allocator, CFStringRef originalString,
        CFStringRef charactersToLeaveEscaped,
        CFStringEncoding encoding) {
    (void)allocator;
    if(!originalString) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateStringByReplacingPercentEscapes,
        LC32_CF_HOST(originalString),
        LC32_CF_HOST(charactersToLeaveEscaped), LC32_CF_U32(encoding));
}

CFStringRef CFURLCreateStringByReplacingPercentEscapes(
        CFAllocatorRef allocator, CFStringRef originalString,
        CFStringRef charactersToLeaveEscaped) {
    return CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
        allocator, originalString, charactersToLeaveEscaped,
        kCFStringEncodingUTF8);
}

Boolean CFNumberGetValue(CFNumberRef number, CFNumberType type,
                         void *valuePointer) {
    if(!number || !valuePointer) return false;
    return LC32_CF_CALL(LC32CoreFoundationOpNumberGetValue,
        LC32_CF_HOST(number), LC32_CF_U32(type),
        LC32_CF_U32((uintptr_t)valuePointer)) != 0;
}

@interface LC32CFLocalNotificationObserver : NSObject {
    CFNotificationCenterRef _center;
    const void *_observer;
    CFNotificationCallback _callback;
}
- (instancetype)initWithCenter:(CFNotificationCenterRef)center
                       observer:(const void *)observer
                       callback:(CFNotificationCallback)callback;
- (void)lc32_handleNotification:(NSNotification *)notification;
@end

@implementation LC32CFLocalNotificationObserver

- (instancetype)initWithCenter:(CFNotificationCenterRef)center
                       observer:(const void *)observer
                       callback:(CFNotificationCallback)callback {
    self = [super init];
    if(self) {
        _center = center;
        _observer = observer;
        _callback = callback;
    }
    return self;
}

- (void)lc32_handleNotification:(NSNotification *)notification {
    if(!_callback) return;
    _callback(_center, (void *)_observer,
        (CFNotificationName)notification.name,
        (const void *)notification.object,
        (CFDictionaryRef)notification.userInfo);
}

@end

CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void) {
    return (CFNotificationCenterRef)[NSNotificationCenter defaultCenter];
}

void CFNotificationCenterAddObserver(
        CFNotificationCenterRef center, const void *observer,
        CFNotificationCallback callback, CFStringRef name,
        const void *object,
        CFNotificationSuspensionBehavior suspensionBehavior) {
    (void)suspensionBehavior;
    if(!callback) return;
    if(!center) center = CFNotificationCenterGetLocalCenter();

    LC32CFLocalNotificationObserver *trampoline =
        [[LC32CFLocalNotificationObserver alloc]
            initWithCenter:center observer:observer callback:callback];
    [(NSNotificationCenter *)center
        addObserver:trampoline
           selector:@selector(lc32_handleNotification:)
               name:(NSString *)name
             object:(id)object];

    /*
     * CF's selector-style registration remains active until explicitly
     * removed. Flappy does not import the removal API, so retain the small
     * trampoline for the same lifetime instead of relying on the host's
     * modern weak-observer implementation.
     */
    (void)trampoline;
}
