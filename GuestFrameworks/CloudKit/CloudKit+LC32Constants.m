#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

const NSUInteger CKQueryOperationMaximumResults = NSUIntegerMax;

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_CLOUDKIT_OBJECT_CONSTANTS(X) \
    X(CKAccountChangedNotification) \
    X(CKCurrentUserDefaultName) \
    X(CKErrorDomain) \
    X(CKErrorRetryAfterKey) \
    X(CKOwnerDefaultName) \
    X(CKPartialErrorsByItemIDKey) \
    X(CKRecordChangedErrorAncestorRecordKey) \
    X(CKRecordChangedErrorClientRecordKey) \
    X(CKRecordChangedErrorServerRecordKey) \
    X(CKRecordParentKey) \
    X(CKRecordShareKey) \
    X(CKRecordTypeShare) \
    X(CKRecordTypeUserRecord) \
    X(CKRecordZoneDefaultName) \
    X(CKShareThumbnailImageDataKey) \
    X(CKShareTitleKey) \
    X(CKShareTypeKey)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_CLOUDKIT_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeCloudKitObjectConstants(void) {
    LC32LoadHostFramework("CloudKit");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_CLOUDKIT_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_CLOUDKIT_OBJECT_CONSTANTS
