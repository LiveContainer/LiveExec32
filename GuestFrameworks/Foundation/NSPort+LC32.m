#import <Foundation/Foundation+LC32.h>

static id LC32AllocateMachPortPeer(void) {
    uint64_t allocate = LC32Dlsym("LC32_Foundation_AllocateMachPortPeer", YES);
    return allocate ? (id)(uintptr_t)LC32InvokeHostCRet32(allocate) : nil;
}

@implementation NSPort (LC32PortAllocation)
+ (id)alloc {
    return self == [NSPort class] ? LC32AllocateMachPortPeer() : [super alloc];
}
+ (id)allocWithZone:(NSZone *)zone {
    return self == [NSPort class] ? LC32AllocateMachPortPeer() : [super allocWithZone:zone];
}
+ (NSPort *)port { return [[[self alloc] init] autorelease]; }
@end

@implementation NSMachPort (LC32PortAllocation)
+ (id)alloc {
    return self == [NSMachPort class] ? LC32AllocateMachPortPeer() : [super alloc];
}
+ (id)allocWithZone:(NSZone *)zone {
    return self == [NSMachPort class] ? LC32AllocateMachPortPeer() : [super allocWithZone:zone];
}
+ (NSPort *)port { return [[[self alloc] init] autorelease]; }
+ (NSPort *)portWithMachPort:(uint32_t)port {
    return [[[self alloc] initWithMachPort:port] autorelease];
}
+ (NSPort *)portWithMachPort:(uint32_t)port options:(NSMachPortOptions)options {
    return [[[self alloc] initWithMachPort:port options:options] autorelease];
}
@end
