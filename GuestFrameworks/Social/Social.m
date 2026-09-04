#import <Social/Social.h>

/*
 * These legacy service identifiers are weak imports in old applications.
 * Modern simulator runtimes no longer export them, but the identifiers are
 * plain API constants and remain meaningful to the generated Social shims.
 */
NSString * const SLServiceTypeFacebook = @"com.apple.social.facebook";
NSString * const SLServiceTypeTwitter = @"com.apple.social.twitter";
NSString * const SLServiceTypeSinaWeibo = @"com.apple.social.sinaweibo";
NSString * const SLServiceTypeTencentWeibo = @"com.apple.social.tencentweibo";
NSString * const SLServiceTypeLinkedIn = @"com.apple.social.linkedin";
