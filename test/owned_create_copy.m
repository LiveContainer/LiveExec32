#import <CoreFoundation/CoreFoundation.h>

#include <stdio.h>

int main(void) {
    const char payload[] =
        "LC32 Create/Copy ownership must survive an earlier release";
    CFStringRef original = CFStringCreateWithCString(
        kCFAllocatorDefault, payload, kCFStringEncodingUTF8);
    CFStringRef copy = original
        ? CFStringCreateCopy(kCFAllocatorDefault, original)
        : NULL;

    /* Immutable CF strings normally satisfy Copy by retaining themselves.
     * This deliberately exercises an owned native result whose guest proxy
     * already exists. */
    const Boolean reusedProxy = original && copy && original == copy;
    if(original) CFRelease(original);

    const CFIndex expectedLength = (CFIndex)(sizeof(payload) - 1);
    const Boolean survivedFirstRelease = copy &&
        CFStringGetLength(copy) == expectedLength &&
        CFStringHasPrefix(copy, CFSTR("LC32 Create/Copy"));
    printf("owned-copy-reuses-proxy: %s\n",
           reusedProxy ? "PASS" : "FAIL");
    printf("owned-copy-survives-first-release: %s\n",
           survivedFirstRelease ? "PASS" : "FAIL");

    if(copy) CFRelease(copy);
    return !(reusedProxy && survivedFirstRelease);
}
