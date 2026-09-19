#import <Foundation/Foundation.h>
#import "MachPort.h"

// NSMachPort is explicitly weak-unavailable. Keep it behind an ordinary
// NSPort peer so the bridge can acquire a weak receiver lease without changing
// its dead-object checks or retaining a port for the lifetime of the process.
@interface LC32MachPortPeer : NSPort {
    NSMachPort *_port;
}
@end

@implementation LC32MachPortPeer
- (Class)class { return [NSMachPort class]; }
- (BOOL)isKindOfClass:(Class)cls {
    return cls == [NSMachPort class] || [super isKindOfClass:cls];
}
- (instancetype)init {
    self = [super init];
    if(self) _port = [[NSMachPort alloc] init];
    if(!_port) { [self release]; return nil; }
    return self;
}
- (instancetype)initWithMachPort:(uint32_t)port {
    return [self initWithMachPort:port options:NSMachPortDeallocateNone];
}
- (instancetype)initWithMachPort:(uint32_t)port options:(NSMachPortOptions)options {
    self = [super init];
    if(self) _port = [[NSMachPort alloc] initWithMachPort:port options:options];
    if(!_port) { [self release]; return nil; }
    return self;
}
- (uint32_t)machPort { return _port.machPort; }
- (BOOL)isValid { return _port.valid; }
- (void)invalidate {
    const BOOL wasValid = _port.valid;
    [_port invalidate];
    if(wasValid) [[NSNotificationCenter defaultCenter]
        postNotificationName:NSPortDidBecomeInvalidNotification object:self];
}
- (void)setDelegate:(id<NSPortDelegate>)delegate { [_port setDelegate:(id)delegate]; }
- (id<NSPortDelegate>)delegate { return _port.delegate; }
- (void)scheduleInRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode {
    [_port scheduleInRunLoop:loop forMode:mode];
}
- (void)removeFromRunLoop:(NSRunLoop *)loop forMode:(NSRunLoopMode)mode {
    [_port removeFromRunLoop:loop forMode:mode];
}
- (NSUInteger)reservedSpaceLength { return _port.reservedSpaceLength; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSUInteger)hash { return _port.hash; }
- (BOOL)isEqual:(id)other {
    if(other == self) return YES;
    if([other isKindOfClass:[LC32MachPortPeer class]])
        other = ((LC32MachPortPeer *)other)->_port;
    return [_port isEqual:other];
}
- (BOOL)sendBeforeDate:(NSDate *)date components:(NSMutableArray *)components
        from:(NSPort *)receivePort reserved:(NSUInteger)reserved {
    return [self sendBeforeDate:date msgid:0 components:components
        from:receivePort reserved:reserved];
}
- (BOOL)sendBeforeDate:(NSDate *)date msgid:(NSUInteger)msgid
        components:(NSMutableArray *)components from:(NSPort *)receivePort
        reserved:(NSUInteger)reserved {
    NSMutableArray *nativeComponents = [components mutableCopy];
    for(NSUInteger i = 0; i < nativeComponents.count; ++i) {
        id component = nativeComponents[i];
        if([component isKindOfClass:[LC32MachPortPeer class]])
            nativeComponents[i] = ((LC32MachPortPeer *)component)->_port;
    }
    if([receivePort isKindOfClass:[LC32MachPortPeer class]])
        receivePort = ((LC32MachPortPeer *)receivePort)->_port;
    BOOL result = [_port sendBeforeDate:date msgid:msgid components:nativeComponents
        from:receivePort reserved:reserved];
    [nativeComponents release];
    return result;
}
- (void)encodeWithCoder:(NSCoder *)coder { [_port encodeWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if(self) _port = [[NSMachPort alloc] initWithCoder:coder];
    if(!_port) { [self release]; return nil; }
    return self;
}
- (void)dealloc {
    [_port release];
    [super dealloc];
}
@end

NSPort *LC32AllocateMachPortPeer(void) {
    return [LC32MachPortPeer alloc];
}
