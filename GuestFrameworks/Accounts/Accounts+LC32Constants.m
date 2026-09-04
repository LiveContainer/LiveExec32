#import <Accounts/Accounts.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_ACCOUNTS_OBJECT_CONSTANTS(X) \
    X(ACAccountStoreDidChangeNotification) \
    X(ACAccountTypeIdentifierFacebook) \
    X(ACAccountTypeIdentifierSinaWeibo) \
    X(ACAccountTypeIdentifierTencentWeibo) \
    X(ACAccountTypeIdentifierTwitter) \
    X(ACErrorDomain) \
    X(ACFacebookAppIdKey) \
    X(ACFacebookAudienceEveryone) \
    X(ACFacebookAudienceFriends) \
    X(ACFacebookAudienceKey) \
    X(ACFacebookAudienceOnlyMe) \
    X(ACFacebookPermissionsKey) \
    X(ACTencentWeiboAppIdKey)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_ACCOUNTS_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeAccountsObjectConstants(void) {
    LC32LoadHostFramework("Accounts");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_ACCOUNTS_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_ACCOUNTS_OBJECT_CONSTANTS
