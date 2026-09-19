#import <Foundation/Foundation.h>

// Only used for guest NSBundle messages, never a process-wide UIKit hook.
NSArray *LC32LoadGuestNib(NSBundle *bundle, NSString *name,
                        id owner, NSDictionary *options);
