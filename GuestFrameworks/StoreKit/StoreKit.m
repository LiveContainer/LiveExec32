#import <StoreKit/StoreKit.h>
#import <LC32/LC32.h>
#include <pthread.h>

NSString *const SKErrorDomain = @"SKErrorDomain";

/* The public symbol's historical wire key is the short string "id". */
NSString *const SKStoreProductParameterITunesItemIdentifier = @"id";
NSString *const SKStoreProductParameterAdvertisingPartnerToken = @"advp";
NSString *const SKStoreProductParameterAffiliateToken = @"at";
NSString *const SKStoreProductParameterCampaignToken = @"ct";
NSString *const SKStoreProductParameterProviderToken = @"pt";

NSString *const SKCloudServiceCapabilitiesDidChangeNotification =
    @"SKCloudServiceCapabilitiesDidChangeNotification";
NSString *const SKStorefrontIdentifierDidChangeNotification =
    @"SKStorefrontIdentifierDidChangeNotification";

SKCloudServiceSetupOptionsKey const SKCloudServiceSetupOptionsActionKey =
    @"action";
SKCloudServiceSetupOptionsKey const
    SKCloudServiceSetupOptionsITunesItemIdentifierKey = @"iTunesItemIdentifier";
SKCloudServiceSetupOptionsKey const SKCloudServiceSetupOptionsAffiliateTokenKey =
    @"affiliateToken";
SKCloudServiceSetupOptionsKey const SKCloudServiceSetupOptionsCampaignTokenKey =
    @"campaignToken";
SKCloudServiceSetupAction const SKCloudServiceSetupActionSubscribe =
    @"subscribe";

NSString *const SKReceiptPropertyIsExpired = @"expired";
NSString *const SKReceiptPropertyIsRevoked = @"revoked";
NSString *const SKReceiptPropertyIsVolumePurchase = @"vpp";

NSTimeInterval SKDownloadTimeRemainingUnknown = -1.0;

static pthread_once_t LC32TerminateForInvalidReceiptOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32TerminateForInvalidReceiptAddress;

static void LC32ResolveTerminateForInvalidReceipt(void) {
    LC32TerminateForInvalidReceiptAddress =
        LC32Dlsym("SKTerminateForInvalidReceipt", YES);
}

void SKTerminateForInvalidReceipt(void) {
    pthread_once(&LC32TerminateForInvalidReceiptOnce,
        LC32ResolveTerminateForInvalidReceipt);
    if(LC32TerminateForInvalidReceiptAddress) {
        (void)LC32InvokeHostCRet32(LC32TerminateForInvalidReceiptAddress);
    }
}
