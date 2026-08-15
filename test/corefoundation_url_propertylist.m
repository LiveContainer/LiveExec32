#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    CFURLRef base = CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("https://example.test/a/"), NULL);
    CFURLRef relative = CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("../b?q=one%20two"), base);
    check("url-create-with-string", base && relative &&
        [[(NSURL *)relative absoluteString]
            isEqualToString:@"https://example.test/b?q=one%20two"]);

    const UInt8 latin1URL[] = {
        'h', 't', 't', 'p', ':', '/', '/', 'e', 'x', 'a', 'm', 'p', 'l', 'e',
        '.', 't', 'e', 's', 't', '/', 'c', 'a', 'f', 0xe9,
    };
    CFURLRef bytesURL = CFURLCreateWithBytes(kCFAllocatorDefault,
        latin1URL, sizeof(latin1URL), kCFStringEncodingISOLatin1, NULL);
    NSString *bytesAbsolute = [(NSURL *)bytesURL absoluteString];
    check("url-create-with-bytes-encoding", bytesURL &&
        [bytesAbsolute hasSuffix:@"/caf%C3%A9"]);

    CFStringRef decodedAll =
        CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault,
            CFSTR("one%20two%2Fthree"), CFSTR(""));
    CFStringRef decodedSelective =
        CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault,
            CFSTR("one%20two%2Fthree"), CFSTR("/"));
    CFStringRef decodedLatin1 =
        CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
            kCFAllocatorDefault, (CFStringRef)@"caf%E9", CFSTR(""),
            kCFStringEncodingISOLatin1);
    check("url-percent-decode-all",
        [(NSString *)decodedAll isEqualToString:@"one two/three"]);
    check("url-percent-decode-preserve",
        [(NSString *)decodedSelective isEqualToString:@"one two%2Fthree"]);
    check("url-percent-decode-encoding",
        [(NSString *)decodedLatin1 isEqualToString:@"caf\u00e9"]);

    CFMutableStringRef whitespace = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR(" \t\r\ninside \n"));
    CFStringTrimWhitespace(whitespace);
    check("string-trim-whitespace",
        [(NSString *)whitespace isEqualToString:@"inside"]);

    NSDictionary *leaf = [NSDictionary dictionaryWithObject:@"value"
                                                       forKey:@"key"];
    NSArray *source = [NSArray arrayWithObject:leaf];
    CFPropertyListRef immutable = CFPropertyListCreateDeepCopy(
        kCFAllocatorDefault, (CFPropertyListRef)source,
        kCFPropertyListImmutable);
    CFPropertyListRef mutableContainers = CFPropertyListCreateDeepCopy(
        kCFAllocatorDefault, (CFPropertyListRef)source,
        kCFPropertyListMutableContainers);
    CFPropertyListRef mutableLeaves = CFPropertyListCreateDeepCopy(
        kCFAllocatorDefault, (CFPropertyListRef)source,
        kCFPropertyListMutableContainersAndLeaves);

    BOOL immutableContent = [(NSArray *)immutable isEqual:source];
    [(NSMutableArray *)mutableContainers addObject:@"extra"];
    NSMutableDictionary *copiedLeaf =
        [(NSMutableArray *)mutableContainers objectAtIndex:0];
    [copiedLeaf setObject:@"changed" forKey:@"key"];
    NSMutableString *copiedString =
        [[(NSMutableArray *)mutableLeaves objectAtIndex:0]
            objectForKey:@"key"];
    [copiedString appendString:@"!"];
    check("property-list-deep-copy-content", immutableContent);
    check("property-list-deep-copy-containers",
        [(NSMutableArray *)mutableContainers count] == 2 &&
        [[copiedLeaf objectForKey:@"key"] isEqualToString:@"changed"] &&
        [[leaf objectForKey:@"key"] isEqualToString:@"value"]);
    check("property-list-deep-copy-leaves",
        [copiedString isEqualToString:@"value!"] &&
        [[leaf objectForKey:@"key"] isEqualToString:@"value"]);

    if(base) CFRelease(base);
    if(relative) CFRelease(relative);
    if(bytesURL) CFRelease(bytesURL);
    if(decodedAll) CFRelease(decodedAll);
    if(decodedSelective) CFRelease(decodedSelective);
    if(decodedLatin1) CFRelease(decodedLatin1);
    if(whitespace) CFRelease(whitespace);
    if(immutable) CFRelease(immutable);
    if(mutableContainers) CFRelease(mutableContainers);
    if(mutableLeaves) CFRelease(mutableLeaves);

    [pool drain];
    return failures != 0;
}
