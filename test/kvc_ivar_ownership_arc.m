#import <Foundation/Foundation.h>

extern void LC32TestSetHostValue(id owner, id value, NSString *key);
extern BOOL LC32TestIvarCheck(const char *name, BOOL passed);
extern void *LC32TestCreateNativePool(void);
extern void LC32TestDrainNativePool(void *pool);

@interface LC32ARCOutletOwner : NSObject {
    id strongOutlet;
    __weak id weakOutlet;
    __unsafe_unretained id unsafeOutlet;
}
- (id)strongValue;
- (id)weakValue;
- (id)unsafeValue;
@end
@implementation LC32ARCOutletOwner
- (id)strongValue { return strongOutlet; }
- (id)weakValue { return weakOutlet; }
- (id)unsafeValue { return unsafeOutlet; }
@end

BOOL LC32TestARCIvarOwnership(void) {
    LC32ARCOutletOwner *owner = [LC32ARCOutletOwner new];
    __weak id weakWitness;
    void *nativePool = LC32TestCreateNativePool();
    @autoreleasepool {
        NSObject *value = [NSObject new];
        weakWitness = value;
        LC32TestSetHostValue(owner, value, @"strongOutlet");
    }
    LC32TestDrainNativePool(nativePool);
    nativePool = LC32TestCreateNativePool();
    BOOL passed;
    @autoreleasepool {
        passed = LC32TestIvarCheck("arc-strong-retains",
            weakWitness != nil && owner.strongValue == weakWitness);
    }
    LC32TestDrainNativePool(nativePool);
    nativePool = LC32TestCreateNativePool();
    @autoreleasepool { LC32TestSetHostValue(owner, nil, @"strongOutlet"); }
    LC32TestDrainNativePool(nativePool);
    passed &= LC32TestIvarCheck("arc-strong-clears", weakWitness == nil);
    nativePool = LC32TestCreateNativePool();
    @autoreleasepool {
        NSObject *value = [NSObject new];
        weakWitness = value;
        LC32TestSetHostValue(owner, value, @"weakOutlet");
        passed &= LC32TestIvarCheck("arc-weak-assignment", owner.weakValue == value);
    }
    LC32TestDrainNativePool(nativePool);
    passed &= LC32TestIvarCheck("arc-weak-zeroes",
        weakWitness == nil && owner.weakValue == nil);
    nativePool = LC32TestCreateNativePool();
    @autoreleasepool {
        NSObject *value = [NSObject new];
        weakWitness = value;
        LC32TestSetHostValue(owner, value, @"unsafeOutlet");
        passed &= LC32TestIvarCheck("arc-unsafe-assignment", owner.unsafeValue == value);
    }
    LC32TestDrainNativePool(nativePool);
    passed &= LC32TestIvarCheck("arc-unsafe-does-not-retain", weakWitness == nil);
    LC32TestSetHostValue(owner, nil, @"unsafeOutlet");
    return passed;
}
