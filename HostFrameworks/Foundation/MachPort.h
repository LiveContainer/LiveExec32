#import <Foundation/Foundation.h>

// Returns an uninitialized +1 peer; the guest chooses the port initializer.
FOUNDATION_EXPORT NSPort *LC32AllocateMachPortPeer(void) NS_RETURNS_RETAINED;
