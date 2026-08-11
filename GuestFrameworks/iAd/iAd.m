#import <iAd/iAd.h>

/*
 * These legacy constants' values intentionally differ from their exported
 * symbol names.  Older iAd clients compare the strings, so preserve the
 * values used by iOS rather than manufacturing names from the symbols.
 */
NSString *const ADBannerContentSizeIdentifierPortrait =
    @"ADBannerContentSizePortrait";
NSString *const ADBannerContentSizeIdentifierLandscape =
    @"ADBannerContentSizeLandscape";
