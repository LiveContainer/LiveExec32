#import <SceneKit/SceneKit.h>
#import <LC32/LC32.h>

@interface NSValue (LC32NativeSizedValue)
- (void)getValue:(void *)value size:(NSUInteger)size;
@end

static void LC32GetSceneValue(NSValue *box, void *value, uint32_t size) {
    // iOS SceneKit's layouts are unchanged across the two ABIs. Use bounded
    // native storage instead of the generic bridge's double-HFA return path.
    // The size-taking API also rejects a larger, mismatched NSValue safely.
    LC32HostSizedIndirectDescriptor descriptor;
    LC32InitializeHostSizedIndirectDescriptor(&descriptor, value, size);
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(&hostSelector, @selector(getValue:size:), NO);
    LC32InvokeHostSelector(box.host_self, selector,
        LC32HostSizedIndirectArgument(&descriptor), (uint64_t)size, (uint64_t)0);
}

@implementation NSValue (LC32SceneKit)
+ (NSValue *)valueWithSCNVector3:(SCNVector3)value {
    return [self valueWithBytes:&value objCType:@encode(SCNVector3)];
}
- (SCNVector3)SCNVector3Value {
    SCNVector3 value = {0};
    LC32GetSceneValue(self, &value, sizeof(value));
    return value;
}
+ (NSValue *)valueWithSCNVector4:(SCNVector4)value {
    return [self valueWithBytes:&value objCType:@encode(SCNVector4)];
}
- (SCNVector4)SCNVector4Value {
    SCNVector4 value = {0};
    LC32GetSceneValue(self, &value, sizeof(value));
    return value;
}
+ (NSValue *)valueWithSCNMatrix4:(SCNMatrix4)value {
    return [self valueWithBytes:&value objCType:@encode(SCNMatrix4)];
}
- (SCNMatrix4)SCNMatrix4Value {
    SCNMatrix4 value = {0};
    LC32GetSceneValue(self, &value, sizeof(value));
    return value;
}
@end
