#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

@implementation NSFileManager (LC32Initialization)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)init {
    if(LC32ObjCTraceEnabled()) {
        printf("DBG: call [%s %s]\n",
            class_getName(self.class), sel_getName(_cmd));
    }
    static uint64_t hostCommand __attribute__((aligned(8)));
    const uint64_t command = LC32CachedHostSelector(
        &hostCommand, _cmd, NO);
    const uint64_t hostResult = LC32InvokeHostSelector(
        self.host_self, command, (uint64_t)0);
    return LC32AdoptHostInitializerResult(self, hostResult);
}
#pragma clang diagnostic pop

@end
