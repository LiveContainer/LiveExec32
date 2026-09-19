#import "LegacyNibLoading.h"

// UIKit supplies this category at runtime. Keeping this adapter Foundation-only
// also lets its exception filtering be tested without launching a UI process.
@interface NSBundle (LC32NativeNibLoading)
- (NSArray *)loadNibNamed:(NSString *)name owner:(id)owner
                 options:(NSDictionary *)options;
@end

NSArray *LC32LoadGuestNib(NSBundle *bundle, NSString *name,
                        id owner, NSDictionary *options) {
    @try {
        return [bundle loadNibNamed:name owner:owner options:options];
    } @catch(NSException *exception) {
        // Old clients (including OpenFeint) probe an optional landscape nib,
        // then fall back when loading returns nil. Modern UIKit throws here.
        // Preserve every other exception, including decode/awakeFromNib errors
        // and failures for a different, nested nib.
        if([name isKindOfClass:NSString.class] &&
           [exception.name isEqualToString:NSInternalInconsistencyException] &&
           [exception.reason hasPrefix:@"Could not load NIB in bundle:"] &&
           [exception.reason hasSuffix:
               [NSString stringWithFormat:@"with name '%@'", name]]) {
            return nil;
        }
        @throw;
    }
}
