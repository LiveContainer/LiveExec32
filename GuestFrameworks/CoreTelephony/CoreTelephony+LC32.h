// Xcode's modern iPhoneOS SDK no longer ships a CoreTelephony umbrella
// header, while iOS 10 did. Reconstruct the public subset used by the
// captured guest classes.
#import <CoreTelephony/CTCall.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTCellularData.h>
#import <CoreTelephony/CTSubscriber.h>
#import <CoreTelephony/CTSubscriberInfo.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
