#import <UserNotifications/UserNotifications.h>

#define LC32_USERNOTIFICATIONS_STRING(symbol, value) \
    NSString *const LC32_USERNOTIFICATIONS_##symbol \
        __asm__("_" #symbol) = value;

LC32_USERNOTIFICATIONS_STRING(UNErrorDomain, @"UNErrorDomain")
LC32_USERNOTIFICATIONS_STRING(
    UNNotificationAttachmentOptionsThumbnailClippingRectKey,
    @"thumbnailClippingRect")
LC32_USERNOTIFICATIONS_STRING(
    UNNotificationAttachmentOptionsThumbnailHiddenKey, @"thumbnailHidden")
LC32_USERNOTIFICATIONS_STRING(
    UNNotificationAttachmentOptionsThumbnailTimeKey, @"thumbnailTime")
LC32_USERNOTIFICATIONS_STRING(
    UNNotificationAttachmentOptionsTypeHintKey, @"typeHint")
LC32_USERNOTIFICATIONS_STRING(UNNotificationDefaultActionIdentifier,
    @"com.apple.UNNotificationDefaultActionIdentifier")
LC32_USERNOTIFICATIONS_STRING(UNNotificationDismissActionIdentifier,
    @"com.apple.UNNotificationDismissActionIdentifier")

#undef LC32_USERNOTIFICATIONS_STRING
