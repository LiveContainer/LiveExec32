#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

/*
 * Apple LLVM versions used by some early iOS games emitted blocks whose
 * flags advertise a signature but whose descriptor contains a null signature
 * pointer.  A raw guest-to-host conversion cannot safely infer that missing
 * ABI.  This API does define it, however, so capture the legacy callback in a
 * block emitted by the current guest compiler.  The generic bridge can read
 * the wrapper's `void (^)(NSNotification *)` signature and its normal copy
 * helper keeps the original callback alive for as long as Foundation does.
 */
@implementation NSNotificationCenter (LC32BlockCompatibility)

- (id)addObserverForName:(NSString *)name
                  object:(id)object
                   queue:(NSOperationQueue *)queue
              usingBlock:(void (^)(NSNotification *notification))block {
    void (^typedBlock)(NSNotification *) = nil;
    if(block) {
        typedBlock = ^(NSNotification *notification) {
            block(notification);
        };
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    id guestResult = LC32InvokeHostObjectSelector(
        [self host_self], command,
        [name host_self], [object host_self], [queue host_self],
        [typedBlock host_self], (uint64_t)0);
    return LC32ReturnBorrowedGuestObject(guestResult);
}

@end
