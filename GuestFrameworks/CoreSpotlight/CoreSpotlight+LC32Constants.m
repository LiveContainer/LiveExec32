#import <CoreSpotlight/CoreSpotlight.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const CSIndexErrorDomain)
LC32_CONST_STR_DECL(NSString *const CSMailboxArchive)
LC32_CONST_STR_DECL(NSString *const CSMailboxDrafts)
LC32_CONST_STR_DECL(NSString *const CSMailboxInbox)
LC32_CONST_STR_DECL(NSString *const CSMailboxJunk)
LC32_CONST_STR_DECL(NSString *const CSMailboxSent)
LC32_CONST_STR_DECL(NSString *const CSMailboxTrash)
LC32_CONST_STR_DECL(NSString *const CSQueryContinuationActionType)
LC32_CONST_STR_DECL(NSString *const CSSearchQueryErrorDomain)
LC32_CONST_STR_DECL(NSString *const CSSearchQueryString)
LC32_CONST_STR_DECL(NSString *const CSSearchableItemActionType)
LC32_CONST_STR_DECL(NSString *const CSSearchableItemActivityIdentifier)

/* Generated from the 10.3 framework's 149.5.6 project version. */
double CoreSpotlightVersionNumber = 149.5;
const unsigned char CoreSpotlightVersionString[] =
    "@(#)PROGRAM:CoreSpotlight  PROJECT:CoreSpotlight-149.5.6\n";

__attribute__((constructor)) static void LC32InitializeCoreSpotlightConstants(void) {
    LC32LoadHostFramework("CoreSpotlight");
    LC32_CONST_STR_INIT(CSIndexErrorDomain);
    LC32_CONST_STR_INIT(CSMailboxArchive);
    LC32_CONST_STR_INIT(CSMailboxDrafts);
    LC32_CONST_STR_INIT(CSMailboxInbox);
    LC32_CONST_STR_INIT(CSMailboxJunk);
    LC32_CONST_STR_INIT(CSMailboxSent);
    LC32_CONST_STR_INIT(CSMailboxTrash);
    LC32_CONST_STR_INIT(CSQueryContinuationActionType);
    LC32_CONST_STR_INIT(CSSearchQueryErrorDomain);
    LC32_CONST_STR_INIT(CSSearchQueryString);
    LC32_CONST_STR_INIT(CSSearchableItemActionType);
    LC32_CONST_STR_INIT(CSSearchableItemActivityIdentifier);
}

#pragma clang diagnostic pop
