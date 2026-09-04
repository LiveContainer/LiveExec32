#import <PassKit/PassKit.h>

#define LC32_PASSKIT_STRING(symbol, value) \
    NSString *const LC32_PASSKIT_##symbol __asm__("_" #symbol) = value;

LC32_PASSKIT_STRING(PKEncryptionSchemeECC_V2, @"EV_ECC_v2")
LC32_PASSKIT_STRING(PKEncryptionSchemeRSA_V2, @"EV_RSA_v2")
LC32_PASSKIT_STRING(PKPassKitErrorDomain, @"PKPassKitErrorDomain")
LC32_PASSKIT_STRING(PKPassLibraryAddedPassesUserInfoKey,
    @"PKPassLibraryAddedPassesUserInfo")
LC32_PASSKIT_STRING(PKPassLibraryDidChangeNotification,
    @"PKPassLibraryDidChangeNotification")
LC32_PASSKIT_STRING(PKPassLibraryPassTypeIdentifierUserInfoKey,
    @"PKPassLibraryPassTypeIdentifierUserInfo")
LC32_PASSKIT_STRING(PKPassLibraryRemotePaymentPassesDidChangeNotification,
    @"PKPassLibraryRemotePaymentPassesDidChange")
LC32_PASSKIT_STRING(PKPassLibraryRemovedPassInfosUserInfoKey,
    @"PKPassLibraryRemovedPassInfosUserInfo")
LC32_PASSKIT_STRING(PKPassLibraryReplacementPassesUserInfoKey,
    @"PKPassLibraryReplacementPassesUserInfo")
LC32_PASSKIT_STRING(PKPassLibrarySerialNumberUserInfoKey,
    @"PKPassLibrarySerialNumberUserInfo")
LC32_PASSKIT_STRING(PKPaymentNetworkAmex, @"AmEx")
LC32_PASSKIT_STRING(PKPaymentNetworkCarteBancaire, @"CarteBancaire")
LC32_PASSKIT_STRING(PKPaymentNetworkChinaUnionPay, @"ChinaUnionPay")
LC32_PASSKIT_STRING(PKPaymentNetworkDiscover, @"Discover")
LC32_PASSKIT_STRING(PKPaymentNetworkIDCredit, @"iD")
LC32_PASSKIT_STRING(PKPaymentNetworkInterac, @"Interac")
LC32_PASSKIT_STRING(PKPaymentNetworkJCB, @"JCB")
LC32_PASSKIT_STRING(PKPaymentNetworkMasterCard, @"MasterCard")
LC32_PASSKIT_STRING(PKPaymentNetworkPrivateLabel, @"PrivateLabel")
LC32_PASSKIT_STRING(PKPaymentNetworkQuicPay, @"QUICPay")
LC32_PASSKIT_STRING(PKPaymentNetworkSuica, @"Suica")
LC32_PASSKIT_STRING(PKPaymentNetworkVisa, @"Visa")

#undef LC32_PASSKIT_STRING
