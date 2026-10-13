#import <Foundation/Foundation+LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

static NSDictionary *LC32AttributedStringAttributes(NSDictionary *attributes) {
    return [(NSDictionary *)LC32CopyDictionaryWithObjectEntries(
        (CFDictionaryRef)attributes) autorelease];
}

// The class-cluster initializers are absent from the generated method dump.
// Keep native replacement-object ownership through the usual initializer path;
// NSMutableAttributedString inherits these bridges too.
@implementation NSAttributedString (LC32Initializers)

- (instancetype)initWithString:(NSString *)string {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t result = LC32InvokeHostSelector(
        self.host_self, selector, string.host_self, (uint64_t)0);
    return LC32AdoptHostInitializerResult(self, result);
}

- (instancetype)initWithString:(NSString *)string attributes:(NSDictionary *)attributes {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t result = LC32InvokeHostSelector(
        self.host_self, selector, string.host_self,
        LC32AttributedStringAttributes(attributes).host_self, (uint64_t)0);
    return LC32AdoptHostInitializerResult(self, result);
}

- (instancetype)initWithAttributedString:(NSAttributedString *)string {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    const uint64_t result = LC32InvokeHostSelector(
        self.host_self, selector, string.host_self, (uint64_t)0);
    return LC32AdoptHostInitializerResult(self, result);
}

@end

@implementation NSMutableAttributedString (LC32Attributes)

- (void)setAttributes:(NSDictionary *)attributes range:(NSRange)range {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    LC32NSRange64 hostRange = LC32WidenNSRange(range);
    LC32InvokeHostSelector(self.host_self, selector,
        LC32AttributedStringAttributes(attributes).host_self,
        LC32HostAggregateArgument(&hostRange), (uint64_t)0);
}

- (void)addAttributes:(NSDictionary *)attributes range:(NSRange)range {
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, _cmd, NO);
    LC32NSRange64 hostRange = LC32WidenNSRange(range);
    LC32InvokeHostSelector(self.host_self, selector,
        LC32AttributedStringAttributes(attributes).host_self,
        LC32HostAggregateArgument(&hostRange), (uint64_t)0);
}

@end
