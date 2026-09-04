#import <MessageUI/MessageUI.h>

#define LC32_MESSAGEUI_STRING(symbol, value) \
    NSString *const LC32_MESSAGEUI_##symbol __asm__("_" #symbol) = value;

LC32_MESSAGEUI_STRING(MFMailComposeErrorDomain, @"MFMailComposeErrorDomain")
LC32_MESSAGEUI_STRING(MFMessageComposeViewControllerAttachmentAlternateFilename,
    @"__kMFMessageComposeViewControllerAttachmentAlternateFilename")
LC32_MESSAGEUI_STRING(MFMessageComposeViewControllerAttachmentURL,
    @"__kMFMessageComposeViewControllerAttachmentURL")
LC32_MESSAGEUI_STRING(
    MFMessageComposeViewControllerTextMessageAvailabilityDidChangeNotification,
    @"__kMFMessageComposeViewControllerTextMessageAvailabilityDidChangeNotification")
LC32_MESSAGEUI_STRING(MFMessageComposeViewControllerTextMessageAvailabilityKey,
    @"__kMFMessageComposeViewControllerTextMessageAvailabilityKey")

#undef LC32_MESSAGEUI_STRING
