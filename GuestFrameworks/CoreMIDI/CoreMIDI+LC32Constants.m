#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wincompatible-pointer-types"

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_COREMIDI_OBJECT_CONSTANTS(X) \
    X(MIDINetworkBonjourServiceType) \
    X(MIDINetworkNotificationContactsDidChange) \
    X(MIDINetworkNotificationSessionDidChange) \
    X(kMIDIPropertyAdvanceScheduleTimeMuSec) \
    X(kMIDIPropertyCanRoute) \
    X(kMIDIPropertyConnectionUniqueID) \
    X(kMIDIPropertyDeviceID) \
    X(kMIDIPropertyDisplayName) \
    X(kMIDIPropertyDriverDeviceEditorApp) \
    X(kMIDIPropertyDriverOwner) \
    X(kMIDIPropertyDriverVersion) \
    X(kMIDIPropertyImage) \
    X(kMIDIPropertyIsBroadcast) \
    X(kMIDIPropertyIsDrumMachine) \
    X(kMIDIPropertyIsEffectUnit) \
    X(kMIDIPropertyIsEmbeddedEntity) \
    X(kMIDIPropertyIsMixer) \
    X(kMIDIPropertyIsSampler) \
    X(kMIDIPropertyManufacturer) \
    X(kMIDIPropertyMaxReceiveChannels) \
    X(kMIDIPropertyMaxSysExSpeed) \
    X(kMIDIPropertyMaxTransmitChannels) \
    X(kMIDIPropertyModel) \
    X(kMIDIPropertyName) \
    X(kMIDIPropertyNameConfiguration) \
    X(kMIDIPropertyOffline) \
    X(kMIDIPropertyPanDisruptsStereo) \
    X(kMIDIPropertyPrivate) \
    X(kMIDIPropertyReceiveChannels) \
    X(kMIDIPropertyReceivesBankSelectLSB) \
    X(kMIDIPropertyReceivesBankSelectMSB) \
    X(kMIDIPropertyReceivesClock) \
    X(kMIDIPropertyReceivesMTC) \
    X(kMIDIPropertyReceivesNotes) \
    X(kMIDIPropertyReceivesProgramChanges) \
    X(kMIDIPropertySingleRealtimeEntity) \
    X(kMIDIPropertySupportsGeneralMIDI) \
    X(kMIDIPropertySupportsMMC) \
    X(kMIDIPropertySupportsShowControl) \
    X(kMIDIPropertyTransmitChannels) \
    X(kMIDIPropertyTransmitsBankSelectLSB) \
    X(kMIDIPropertyTransmitsBankSelectMSB) \
    X(kMIDIPropertyTransmitsClock) \
    X(kMIDIPropertyTransmitsMTC) \
    X(kMIDIPropertyTransmitsNotes) \
    X(kMIDIPropertyTransmitsProgramChanges) \
    X(kMIDIPropertyUniqueID)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_COREMIDI_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeCoreMIDIObjectConstants(void) {
    LC32LoadHostFramework("CoreMIDI");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_COREMIDI_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_COREMIDI_OBJECT_CONSTANTS
