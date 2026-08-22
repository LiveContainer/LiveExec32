@import Foundation;
#import "bridge.h"
#include "../../GuestFrameworks/Foundation/LC32FoundationBridge.h"

#include <cstring>

namespace {

NSString *LC32GuestHomeDirectory() {
    const char *path = getenv("LC32_GUEST_HOME");
    if(path && path[0]) return [NSString stringWithUTF8String:path];
    return NSHomeDirectory();
}

NSString *LC32UserSearchPath(NSSearchPathDirectory directory,
                             BOOL expandTilde) {
    NSString *suffix = nil;
    switch(directory) {
        case NSDocumentDirectory: suffix = @"Documents"; break;
        case NSLibraryDirectory: suffix = @"Library"; break;
        case NSCachesDirectory: suffix = @"Library/Caches"; break;
        case NSApplicationSupportDirectory:
            suffix = @"Library/Application Support"; break;
        case NSAutosavedInformationDirectory:
            suffix = @"Library/Autosave Information"; break;
        case NSDesktopDirectory: suffix = @"Desktop"; break;
        case NSDownloadsDirectory: suffix = @"Downloads"; break;
        case NSInputMethodsDirectory: suffix = @"Library/Input Methods"; break;
        case NSMoviesDirectory: suffix = @"Movies"; break;
        case NSMusicDirectory: suffix = @"Music"; break;
        case NSPicturesDirectory: suffix = @"Pictures"; break;
        case NSSharedPublicDirectory: suffix = @"Public"; break;
        case NSPreferencePanesDirectory:
            suffix = @"Library/PreferencePanes"; break;
        case static_cast<NSSearchPathDirectory>(23):
            suffix = @"Library/Application Scripts"; break;
        default: break;
    }
    if(!suffix) return nil;
    NSString *base = expandTilde ? LC32GuestHomeDirectory() : @"~";
    return [base stringByAppendingPathComponent:suffix];
}

} // namespace

__BEGIN_DECLS

u32 LC32_Foundation_NSTemporaryDirectory() {
    return NSTemporaryDirectory().guest_self;
}

u32 LC32_Foundation_NSHomeDirectory() {
    return LC32GuestHomeDirectory().guest_self;
}

u32 LC32_Foundation_NSClassFromString(u32 low, u32 high, u32) {
    NSString *name = reinterpret_cast<NSString *>(
        static_cast<uintptr_t>(low | (static_cast<u64>(high) << 32)));
    return name ? guest_objc_getClass(name.UTF8String) : 0;
}

u32 LC32_Foundation_NSSelectorFromString(u32 low, u32 high, u32) {
    NSString *name = reinterpret_cast<NSString *>(
        static_cast<uintptr_t>(low | (static_cast<u64>(high) << 32)));
    return name ? guest_sel_registerName(name.UTF8String) : 0;
}

u32 LC32_Foundation_NSSearchPathForDirectoriesInDomains(
        u32 directoryValue, u32 domainMaskValue, u32 stack) {
    const BOOL expandTilde =
        Dynarmic_current_user_callbacks()->MemoryRead32(stack) != 0;
    const NSSearchPathDirectory directory =
        static_cast<NSSearchPathDirectory>(directoryValue);
    const NSSearchPathDomainMask domainMask =
        static_cast<NSSearchPathDomainMask>(domainMaskValue);

    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if(domainMask & NSUserDomainMask) {
        NSString *userPath = LC32UserSearchPath(directory, expandTilde);
        if(userPath) [paths addObject:userPath];
    }
    const NSSearchPathDomainMask remaining =
        domainMask & ~NSUserDomainMask;
    if(remaining) {
        [paths addObjectsFromArray:
            NSSearchPathForDirectoriesInDomains(
                directory, remaining, expandTilde)];
    }
    if(paths.count == 0 && (domainMask & NSUserDomainMask)) {
        [paths addObjectsFromArray:
            NSSearchPathForDirectoriesInDomains(
                directory, NSUserDomainMask, expandTilde)];
    }
    return paths.guest_self;
}

u32 LC32_Foundation_CreateDelayedTimer(u32 guestCall, u32, u32) {
    LC32FoundationDelayedTimerCall call = {};
    if(!guestCall ||
       Dynarmic_mem_1read(guestCall, sizeof(call),
           reinterpret_cast<char *>(&call)) != 0 ||
       call.version != LC32FoundationDelayedTimerABIVersion ||
       call.slotCount != LC32FoundationDelayedTimerSlotCount) {
        return 0;
    }

    id target = reinterpret_cast<id>(static_cast<uintptr_t>(
        call.slots[LC32FoundationDelayedTimerTargetSlot]));
    SEL selector = reinterpret_cast<SEL>(static_cast<uintptr_t>(
        call.slots[LC32FoundationDelayedTimerSelectorSlot]));
    NSTimeInterval interval;
    static_assert(sizeof(interval) == sizeof(uint64_t));
    memcpy(&interval,
        &call.slots[LC32FoundationDelayedTimerIntervalSlot],
        sizeof(interval));
    if(!target || !selector) return 0;

    NSTimer *timer = [NSTimer timerWithTimeInterval:interval
        target:target selector:selector userInfo:nil repeats:NO];
    return timer.guest_self;
}

__END_DECLS
