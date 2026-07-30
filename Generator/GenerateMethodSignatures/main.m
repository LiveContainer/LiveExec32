// Run this inside the emulator with a full iOS 10 filesystem, or on an iOS 10
// device. It captures the 32-bit Objective-C method encodings needed by the
// shim generator, including the correct NSInteger and CGFloat widths.
// Input is read from /private/var/tmp/classes.plist.

@import Darwin;
@import ObjectiveC;
@import MachO;
// @import DaemonUtils;
@import MapKit;
// @import VideoToolbox;
@import LocalAuthentication;
// @import IntentsUI;
@import GLKit;
@import AVFoundation;
// @import GSS;
@import CoreBluetooth;
@import AddressBookUI;
@import CloudKit;
@import Speech;
// @import UserNotificationsUI;
// @import MediaToolbox;
@import CallKit;
@import UIKit;
// @import MediaAccessibility;
@import AVFAudio;
// @import ModuleBase;
// @import MobileCoreServices;
// @import vImage;
@import AudioToolbox;
@import CoreTelephony;
// @import AudioUnit;
@import GameKit;
// @import SharedUtils;
// @import IOKit;
@import CoreData;
// @import CoreMedia;
@import GameController;
@import HealthKit;
// @import AddressBook;
@import Social;
@import WatchConnectivity;
@import CoreMotion;
@import UserNotifications;
@import OpenGLES;
@import GameplayKit;
@import JavaScriptCore;
@import NotificationCenter;
@import CoreAudioKit;
@import MessageUI;
// @import Accelerate;
// @import CoreAudio;
@import PhotosUI;
@import SceneKit;
@import Foundation;
@import AdSupport;
@import MetalPerformanceShaders;
@import MediaPlayer;
@import iAd;
// @import SystemConfiguration;
@import Metal;
// @import NewsstandKit;
@import HomeKit;
@import NetworkExtension;
@import SpriteKit;
@import PushKit;
@import PassKit;
#if __has_include(<WatchKit/WatchKit.h>)
@import WatchKit;
#endif
// @import OpenAL;
@import WebKit;
@import Contacts;
// @import CoreText;
@import VideoSubscriberAccount;
@import Photos;
// @import Security;
@import AVKit;
@import ContactsUI;
@import CoreMIDI;
@import CoreSpotlight;
@import StoreKit;
@import MetalKit;
@import ModelIO;
@import ExternalAccessory;
@import ReplayKit;
@import Messages;
@import Twitter;
@import EventKit;
@import Accounts;
@import QuartzCore;
@import SafariServices;
@import Intents;
// @import MechanismBase;
// @import AssetsLibrary;
@import CoreImage;
// @import CFNetwork;
@import QuickLook;
// @import CoreVideo;
@import CoreLocation;
@import MultipeerConnectivity;
// @import vecLib;
// @import CoreGraphics;
// @import CoreFoundation;
// @import ImageIO;
@import HealthKitUI;
@import EventKitUI;

@interface NSObject(private)
- (NSString *)_methodDescription;
@end

// workaround to skip libdispatch init
@implementation NSUserDefaults(workaround)
+ (instancetype)standardUserDefaults {
    return nil;
}
@end
@implementation NSThread(workaround)
- (void)start {}
@end
@implementation NSNotificationCenter(workaround)
+ (instancetype)defaultCenter {
    return nil;
}
@end

static char *copyXMLEscapedString(const char *value) {
    size_t escapedLength = 0;
    for(const char *cursor = value; *cursor; cursor++) {
        switch(*cursor) {
            case '&':
                escapedLength += strlen("&amp;");
                break;
            case '<':
            case '>':
                escapedLength += strlen("&lt;");
                break;
            default:
                escapedLength++;
                break;
        }
    }

    char *escaped = malloc(escapedLength + 1);
    assert(escaped);
    char *output = escaped;
    for(const char *cursor = value; *cursor; cursor++) {
        const char *replacement = NULL;
        switch(*cursor) {
            case '&':
                replacement = "&amp;";
                break;
            case '<':
                replacement = "&lt;";
                break;
            case '>':
                replacement = "&gt;";
                break;
        }

        if(replacement) {
            size_t replacementLength = strlen(replacement);
            memcpy(output, replacement, replacementLength);
            output += replacementLength;
        } else {
            *output++ = *cursor;
        }
    }
    *output = '\0';
    return escaped;
}

void dumpMethodList(Class cls) {
    if(!cls) {
        printf("Skipping methods for a class that is not present in this runtime\n");
        return;
    }

    BOOL isClass = class_isMetaClass(cls);
    printf("Dumping %s methods of %s\n", isClass ? "class" : "instance", class_getName(cls));
    unsigned int mc = 0;
    Method *mlist = class_copyMethodList(cls, &mc);
    for(int m = 0; m < mc; m++) {
        const char *name = sel_getName(method_getName(mlist[m]));
        const char *signature = method_getTypeEncoding(mlist[m]);
        if(!name || !signature) {
            printf("Skipped method with a missing name or type encoding\n");
            continue;
        }
        if(strchr(name, '_')) {
            printf("Skipped private method: %s %s\n", name, signature);
            continue;
        }

        // Avoid NSString here because ARC is unreliable in this guest.  Some
        // SpriteKit encodings are larger than 4 KiB, so size the escaped
        // strings dynamically instead of using the old fixed stack buffer.
        char *escapedName = copyXMLEscapedString(name);
        char *escapedSignature = copyXMLEscapedString(signature);
        printf("<!--.--> <key>%s</key><string>%s</string>\n",
               escapedName, escapedSignature);
        free(escapedName);
        free(escapedSignature);
    }
    free(mlist);
}

static const char *imagePathForFramework(NSString *framework, char path[PATH_MAX]) {
    const char *name = framework.UTF8String;
    if(!strcmp(name, "AVFAudio")) {
        snprintf(path, PATH_MAX,
                 "/System/Library/Frameworks/AVFoundation.framework/"
                 "Frameworks/AVFAudio.framework/AVFAudio");
    } else {
        snprintf(path, PATH_MAX,
                 "/System/Library/Frameworks/%1$s.framework/%1$s", name);
    }
    return path;
}

int main() {
    // Host diagnostics and guest stdio share the same file descriptors.
    // Line buffering keeps their output from being reordered when redirected.
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IOLBF, 0);
    printf("Hello from 32bit!\n");

/*
libobjc.A.dylib[0x2247e] <+58>:  ldr    r6, [r2]; r6 = _objc_inform
libobjc.A.dylib[0x22480] <+60>:  cmp    r4, #0x0; die == 0
libobjc.A.dylib[0x22482] <+62>:  it     ne; cmp == false
libobjc.A.dylib[0x22484] <+64>:  ldrne  r6, [r1]; r6 == _objc_fatal
*/
/*
    int i;
    const char *objc = "/usr/lib/libobjc.A.dylib";
    for(i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if(!strncmp(name, objc, strlen(objc))) break;
    }
    uintptr_t header = (uintptr_t)_dyld_get_image_header(i);
    //assert((*(uint16_t*)(header + 0x22484)) == 0x680e);
    (*(uint32_t*)(header + 0x8ca2)) = 0;
    // 0x4770: bx lr
    // 0xbf00 : nop
    // 0xE7FFDEFE, 0xBEBE: bkpt
    // invalidate cache
    //__clear_cache((void *)(header + 0x8ca2), (void *)(header + 0x8ca6));
*/
@autoreleasepool {
    NSString *path = @"/private/var/tmp/classes.plist";
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if(!dict) {
        fprintf(stderr, "Unable to read generator input at %s\n", path.UTF8String);
        exit(1);
    }

    printf("<!--.--> <?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    printf("<!--.--> <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
    printf("<!--.--> <plist version=\"1.0\">\n");
    printf("<!--.--> <dict>\n");
    char frameworkPath[PATH_MAX];
    for(NSString *framework in dict) {
        NSMutableDictionary *classes = dict[framework];
        if(classes.count == 0 || [classes[@"_resolved"] boolValue]) continue;
        printf("Dumping framework %s\n", framework.UTF8String);
        imagePathForFramework(framework, frameworkPath);
        void *handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL);
        if(!handle) {
            fprintf(stderr, "%s\n", dlerror());
            abort();
        }

        printf("<!--.--> <key>%s</key>\n", framework.UTF8String);
        printf("<!--.--> <dict>\n");
        for(NSString *className in classes) {
            printf("Dumping class %s\n", className.UTF8String);
            Class cls = NSClassFromString(className);

            printf("<!--.--> <key>%s</key>\n", className.UTF8String);
            printf("<!--.--> <dict>\n");
            printf("<!--.--> <key>+</key>\n");
            printf("<!--.--> <dict>\n");
            dumpMethodList(object_getClass(cls));
            printf("<!--.--> </dict>\n");

            printf("<!--.--> <key>-</key>\n");
            printf("<!--.--> <dict>\n");
            dumpMethodList(cls);
            printf("<!--.--> </dict>\n");
            printf("<!--.--> </dict>\n");
            
        }
        printf("<!--.--> </dict>\n");
        //classes[@"_resolved"] = @(YES);
        //[dict writeToFile:path atomically:NO];
    }
    printf("<!--.--> </dict>\n");
    printf("<!--.--> </plist>\n");
    //[dict writeToFile:path atomically:NO];
    printf("Done!\n");
    exit(0);
}
}
