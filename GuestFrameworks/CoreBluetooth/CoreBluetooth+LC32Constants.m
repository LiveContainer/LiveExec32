#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_COREBLUETOOTH_OBJECT_CONSTANTS(X) \
    X(CBATTErrorDomain) \
    X(CBAdvertisementDataIsConnectable) \
    X(CBAdvertisementDataLocalNameKey) \
    X(CBAdvertisementDataManufacturerDataKey) \
    X(CBAdvertisementDataOverflowServiceUUIDsKey) \
    X(CBAdvertisementDataServiceDataKey) \
    X(CBAdvertisementDataServiceUUIDsKey) \
    X(CBAdvertisementDataSolicitedServiceUUIDsKey) \
    X(CBAdvertisementDataTxPowerLevelKey) \
    X(CBCentralManagerOptionRestoreIdentifierKey) \
    X(CBCentralManagerOptionShowPowerAlertKey) \
    X(CBCentralManagerRestoredStatePeripheralsKey) \
    X(CBCentralManagerRestoredStateScanOptionsKey) \
    X(CBCentralManagerRestoredStateScanServicesKey) \
    X(CBCentralManagerScanOptionAllowDuplicatesKey) \
    X(CBCentralManagerScanOptionSolicitedServiceUUIDsKey) \
    X(CBConnectPeripheralOptionNotifyOnConnectionKey) \
    X(CBConnectPeripheralOptionNotifyOnDisconnectionKey) \
    X(CBConnectPeripheralOptionNotifyOnNotificationKey) \
    X(CBErrorDomain) \
    X(CBPeripheralManagerOptionRestoreIdentifierKey) \
    X(CBPeripheralManagerOptionShowPowerAlertKey) \
    X(CBPeripheralManagerRestoredStateAdvertisementDataKey) \
    X(CBPeripheralManagerRestoredStateServicesKey) \
    X(CBUUIDCharacteristicAggregateFormatString) \
    X(CBUUIDCharacteristicExtendedPropertiesString) \
    X(CBUUIDCharacteristicFormatString) \
    X(CBUUIDCharacteristicUserDescriptionString) \
    X(CBUUIDCharacteristicValidRangeString) \
    X(CBUUIDClientCharacteristicConfigurationString) \
    X(CBUUIDServerCharacteristicConfigurationString)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_COREBLUETOOTH_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeCoreBluetoothObjectConstants(void) {
    LC32LoadHostFramework("CoreBluetooth");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_COREBLUETOOTH_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_COREBLUETOOTH_OBJECT_CONSTANTS
