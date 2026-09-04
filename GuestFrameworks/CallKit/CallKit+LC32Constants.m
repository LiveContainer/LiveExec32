#import <CallKit/CallKit.h>

#define LC32_CALLKIT_STRING(symbol, value) \
    NSString *const LC32_CALLKIT_##symbol __asm__("_" #symbol) = value;

LC32_CALLKIT_STRING(CXErrorDomain, @"com.apple.CallKit.error")
LC32_CALLKIT_STRING(CXErrorDomainCallDirectoryManager,
    @"com.apple.CallKit.error.calldirectorymanager")
LC32_CALLKIT_STRING(CXErrorDomainIncomingCall,
    @"com.apple.CallKit.error.incomingcall")
LC32_CALLKIT_STRING(CXErrorDomainRequestTransaction,
    @"com.apple.CallKit.error.requesttransaction")

#undef LC32_CALLKIT_STRING
