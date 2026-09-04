#import <ExternalAccessory/ExternalAccessory.h>

#define LC32_EXTERNALACCESSORY_STRING(symbol, value) \
    NSString *const LC32_EXTERNALACCESSORY_##symbol \
        __asm__("_" #symbol) = value;

LC32_EXTERNALACCESSORY_STRING(EAAccessoryDidConnectNotification,
    @"EAAccessoryDidConnectNotification")
LC32_EXTERNALACCESSORY_STRING(EAAccessoryDidDisconnectNotification,
    @"EAAccessoryDidDisconnectNotification")
LC32_EXTERNALACCESSORY_STRING(EAAccessoryKey, @"EAAccessoryKey")
LC32_EXTERNALACCESSORY_STRING(EAAccessorySelectedKey,
    @"EAAccessorySelectedKey")
LC32_EXTERNALACCESSORY_STRING(EABluetoothAccessoryPickerErrorDomain,
    @"EABluetoothAccessoryPickerErrorDomain")

#undef LC32_EXTERNALACCESSORY_STRING
