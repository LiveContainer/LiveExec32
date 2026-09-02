#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIDevice (LC32LegacyUniqueIdentifierTest)
- (NSString *)uniqueIdentifier;
@end

static NSUUID *LC32NilIdentifierForVendor(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return nil;
}

int main(void) {
    @autoreleasepool {
        Method method = class_getInstanceMethod(
            UIDevice.class, @selector(identifierForVendor));
        if(!method) return 1;

        IMP original = method_setImplementation(
            method, (IMP)LC32NilIdentifierForVendor);
        UIDevice *device = UIDevice.currentDevice;
        NSString *first = device.uniqueIdentifier;
        NSString *second = device.uniqueIdentifier;
        method_setImplementation(method, original);
        NSString *vendorIdentifier = device.identifierForVendor.UUIDString;
        NSString *third = device.uniqueIdentifier;

        if(first.length == 0 || first.UTF8String == NULL) return 2;
        if(![first isEqualToString:second]) return 3;
        if(vendorIdentifier != nil &&
                ![vendorIdentifier isEqualToString:third]) return 4;
        if(vendorIdentifier == nil && ![first isEqualToString:third]) return 5;
    }
    return 0;
}
