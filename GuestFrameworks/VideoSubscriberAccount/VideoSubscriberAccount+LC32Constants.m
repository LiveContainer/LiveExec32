#import <VideoSubscriberAccount/VideoSubscriberAccount.h>

#define LC32_VIDEOSUBSCRIBER_STRING(symbol, value) \
    NSString *const LC32_VIDEOSUBSCRIBER_##symbol \
        __asm__("_" #symbol) = value;

LC32_VIDEOSUBSCRIBER_STRING(VSAccountProviderAuthenticationSchemeSAML,
    @"SAML")
LC32_VIDEOSUBSCRIBER_STRING(VSCheckAccessOptionPrompt,
    @"VSCheckAccessOptionPrompt")
LC32_VIDEOSUBSCRIBER_STRING(VSErrorDomain, @"VSErrorDomain")
LC32_VIDEOSUBSCRIBER_STRING(VSErrorInfoKeyAccountProviderResponse,
    @"VSErrorInfoKeyAccountProviderResponse")
LC32_VIDEOSUBSCRIBER_STRING(VSErrorInfoKeySAMLResponse,
    @"VSErrorInfoKeySAMLResponse")
LC32_VIDEOSUBSCRIBER_STRING(VSErrorInfoKeySAMLResponseStatus,
    @"VSErrorInfoKeySAMLResponseStatus")
LC32_VIDEOSUBSCRIBER_STRING(VSErrorInfoKeyUnsupportedProviderIdentifier,
    @"VSErrorInfoKeyUnsupportedProviderIdentifier")

#undef LC32_VIDEOSUBSCRIBER_STRING
