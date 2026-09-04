#import <iAd/iAd.h>

NSString *const ADErrorDomain = @"ADErrorDomain";
NSString *const ADClientErrorDomain = @"ADClientErrorDomain";

/*
 * These legacy constants' values intentionally differ from their exported
 * symbol names.  Older iAd clients compare the strings, so preserve the
 * values used by iOS rather than manufacturing names from the symbols.
 */
NSString *const ADBannerContentSizeIdentifierPortrait =
    @"ADBannerContentSizePortrait";
NSString *const ADBannerContentSizeIdentifierLandscape =
    @"ADBannerContentSizeLandscape";
NSString *const ADBannerContentSizeIdentifier320x50 =
    @"ADBannerContentSize320x50";
NSString *const ADBannerContentSizeIdentifier480x32 =
    @"ADBannerContentSize480x32";
