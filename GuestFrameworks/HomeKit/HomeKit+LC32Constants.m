#import <HomeKit/HomeKit.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeAirConditioner)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeAirDehumidifier)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeAirHeater)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeAirHumidifier)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeAirPurifier)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeBridge)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeDoor)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeDoorLock)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeFan)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeGarageDoorOpener)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeIPCamera)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeLightbulb)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeOther)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeOutlet)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeProgrammableSwitch)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeRangeExtender)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeSecuritySystem)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeSensor)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeSwitch)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeThermostat)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeVideoDoorbell)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeWindow)
LC32_CONST_STR_DECL(NSString *const HMAccessoryCategoryTypeWindowCovering)
LC32_CONST_STR_DECL(NSString *const HMActionSetTypeHomeArrival)
LC32_CONST_STR_DECL(NSString *const HMActionSetTypeHomeDeparture)
LC32_CONST_STR_DECL(NSString *const HMActionSetTypeSleep)
LC32_CONST_STR_DECL(NSString *const HMActionSetTypeTriggerOwned)
LC32_CONST_STR_DECL(NSString *const HMActionSetTypeUserDefined)
LC32_CONST_STR_DECL(NSString *const HMActionSetTypeWakeUp)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicKeyPath)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatArray)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatBool)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatData)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatDictionary)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatFloat)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatInt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatString)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatTLV8)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatUInt16)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatUInt32)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatUInt64)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataFormatUInt8)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsArcDegree)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsCelsius)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsFahrenheit)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsLux)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsMicrogramsPerCubicMeter)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsPartsPerMillion)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsPercentage)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicMetadataUnitsSeconds)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicPropertyHidden)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicPropertyReadable)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicPropertySupportsEventNotification)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicPropertyWritable)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeActive)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeAdminOnlyAccess)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeAirParticulateDensity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeAirParticulateSize)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeAirQuality)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeAudioFeedback)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeBatteryLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeBrightness)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCarbonDioxideDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCarbonDioxideLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCarbonDioxidePeakLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCarbonMonoxideDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCarbonMonoxideLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCarbonMonoxidePeakLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeChargingState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeContactState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCoolingThreshold)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentAirPurifierState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentDoorState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentFanState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentHeaterCoolerState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentHeatingCooling)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentHorizontalTilt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentHumidifierDehumidifierState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentLightLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentLockMechanismState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentPosition)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentRelativeHumidity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentSecuritySystemState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentSlatState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentTemperature)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentTilt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeCurrentVerticalTilt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeDehumidifierThreshold)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeDigitalZoom)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeFilterChangeIndication)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeFilterLifeLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeFilterResetChangeIndication)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeFirmwareVersion)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeHardwareVersion)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeHeatingThreshold)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeHoldPosition)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeHue)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeHumidifierThreshold)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeIdentify)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeImageMirroring)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeImageRotation)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeInputEvent)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLabelIndex)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLabelNamespace)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLeakDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLockManagementAutoSecureTimeout)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLockManagementControlPoint)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLockMechanismLastKnownAction)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLockPhysicalControls)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeLogs)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeManufacturer)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeModel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeMotionDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeMute)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeName)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeNightVision)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeNitrogenDioxideDensity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeObstructionDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeOccupancyDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeOpticalZoom)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeOutletInUse)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeOutputState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeOzoneDensity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypePM10Density)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypePM2_5Density)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypePositionState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypePowerState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeRotationDirection)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeRotationSpeed)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSaturation)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSecuritySystemAlarmType)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSelectedStreamConfiguration)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSerialNumber)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSetupStreamEndpoint)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSlatType)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSmokeDetected)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSoftwareVersion)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeStatusActive)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeStatusFault)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeStatusJammed)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeStatusLowBattery)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeStatusTampered)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeStreamingStatus)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSulphurDioxideDensity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSupportedAudioStreamConfiguration)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSupportedRTPConfiguration)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSupportedVideoStreamConfiguration)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeSwingMode)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetAirPurifierState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetDoorState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetFanState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetHeaterCoolerState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetHeatingCooling)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetHorizontalTilt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetHumidifierDehumidifierState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetLockMechanismState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetPosition)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetRelativeHumidity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetSecuritySystemState)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetTemperature)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetTilt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTargetVerticalTilt)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeTemperatureUnits)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeVersion)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeVolatileOrganicCompoundDensity)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeVolume)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicTypeWaterLevel)
LC32_CONST_STR_DECL(NSString *const HMCharacteristicValueKeyPath)
LC32_CONST_STR_DECL(NSString *const HMErrorDomain)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeAccessoryInformation)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeAirPurifier)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeAirQualitySensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeBattery)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeCameraControl)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeCameraRTPStreamManagement)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeCarbonDioxideSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeCarbonMonoxideSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeContactSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeDoor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeDoorbell)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeFan)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeFilterMaintenance)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeGarageDoorOpener)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeHeaterCooler)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeHumidifierDehumidifier)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeHumiditySensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeLabel)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeLeakSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeLightSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeLightbulb)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeLockManagement)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeLockMechanism)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeMicrophone)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeMotionSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeOccupancySensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeOutlet)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeSecuritySystem)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeSlats)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeSmokeSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeSpeaker)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeStatefulProgrammableSwitch)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeStatelessProgrammableSwitch)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeSwitch)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeTemperatureSensor)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeThermostat)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeVentilationFan)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeWindow)
LC32_CONST_STR_DECL(NSString *const HMServiceTypeWindowCovering)
LC32_CONST_STR_DECL(NSString *const HMSignificantEventSunrise)
LC32_CONST_STR_DECL(NSString *const HMSignificantEventSunset)
LC32_CONST_STR_DECL(NSString *const HMUserFailedAccessoriesKey)

__attribute__((constructor)) static void LC32InitializeHomeKitConstants(void) {
    LC32LoadHostFramework("HomeKit");
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeAirConditioner);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeAirDehumidifier);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeAirHeater);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeAirHumidifier);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeAirPurifier);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeBridge);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeDoor);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeDoorLock);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeFan);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeGarageDoorOpener);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeIPCamera);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeLightbulb);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeOther);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeOutlet);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeProgrammableSwitch);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeRangeExtender);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeSecuritySystem);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeSensor);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeSwitch);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeThermostat);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeVideoDoorbell);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeWindow);
    LC32_CONST_STR_INIT(HMAccessoryCategoryTypeWindowCovering);
    LC32_CONST_STR_INIT(HMActionSetTypeHomeArrival);
    LC32_CONST_STR_INIT(HMActionSetTypeHomeDeparture);
    LC32_CONST_STR_INIT(HMActionSetTypeSleep);
    LC32_CONST_STR_INIT(HMActionSetTypeTriggerOwned);
    LC32_CONST_STR_INIT(HMActionSetTypeUserDefined);
    LC32_CONST_STR_INIT(HMActionSetTypeWakeUp);
    LC32_CONST_STR_INIT(HMCharacteristicKeyPath);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatArray);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatBool);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatData);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatDictionary);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatFloat);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatInt);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatString);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatTLV8);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatUInt16);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatUInt32);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatUInt64);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataFormatUInt8);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsArcDegree);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsCelsius);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsFahrenheit);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsLux);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsMicrogramsPerCubicMeter);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsPartsPerMillion);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsPercentage);
    LC32_CONST_STR_INIT(HMCharacteristicMetadataUnitsSeconds);
    LC32_CONST_STR_INIT(HMCharacteristicPropertyHidden);
    LC32_CONST_STR_INIT(HMCharacteristicPropertyReadable);
    LC32_CONST_STR_INIT(HMCharacteristicPropertySupportsEventNotification);
    LC32_CONST_STR_INIT(HMCharacteristicPropertyWritable);
    LC32_CONST_STR_INIT(HMCharacteristicTypeActive);
    LC32_CONST_STR_INIT(HMCharacteristicTypeAdminOnlyAccess);
    LC32_CONST_STR_INIT(HMCharacteristicTypeAirParticulateDensity);
    LC32_CONST_STR_INIT(HMCharacteristicTypeAirParticulateSize);
    LC32_CONST_STR_INIT(HMCharacteristicTypeAirQuality);
    LC32_CONST_STR_INIT(HMCharacteristicTypeAudioFeedback);
    LC32_CONST_STR_INIT(HMCharacteristicTypeBatteryLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeBrightness);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCarbonDioxideDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCarbonDioxideLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCarbonDioxidePeakLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCarbonMonoxideDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCarbonMonoxideLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCarbonMonoxidePeakLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeChargingState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeContactState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCoolingThreshold);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentAirPurifierState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentDoorState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentFanState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentHeaterCoolerState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentHeatingCooling);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentHorizontalTilt);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentHumidifierDehumidifierState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentLightLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentLockMechanismState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentPosition);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentRelativeHumidity);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentSecuritySystemState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentSlatState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentTemperature);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentTilt);
    LC32_CONST_STR_INIT(HMCharacteristicTypeCurrentVerticalTilt);
    LC32_CONST_STR_INIT(HMCharacteristicTypeDehumidifierThreshold);
    LC32_CONST_STR_INIT(HMCharacteristicTypeDigitalZoom);
    LC32_CONST_STR_INIT(HMCharacteristicTypeFilterChangeIndication);
    LC32_CONST_STR_INIT(HMCharacteristicTypeFilterLifeLevel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeFilterResetChangeIndication);
    LC32_CONST_STR_INIT(HMCharacteristicTypeFirmwareVersion);
    LC32_CONST_STR_INIT(HMCharacteristicTypeHardwareVersion);
    LC32_CONST_STR_INIT(HMCharacteristicTypeHeatingThreshold);
    LC32_CONST_STR_INIT(HMCharacteristicTypeHoldPosition);
    LC32_CONST_STR_INIT(HMCharacteristicTypeHue);
    LC32_CONST_STR_INIT(HMCharacteristicTypeHumidifierThreshold);
    LC32_CONST_STR_INIT(HMCharacteristicTypeIdentify);
    LC32_CONST_STR_INIT(HMCharacteristicTypeImageMirroring);
    LC32_CONST_STR_INIT(HMCharacteristicTypeImageRotation);
    LC32_CONST_STR_INIT(HMCharacteristicTypeInputEvent);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLabelIndex);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLabelNamespace);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLeakDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLockManagementAutoSecureTimeout);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLockManagementControlPoint);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLockMechanismLastKnownAction);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLockPhysicalControls);
    LC32_CONST_STR_INIT(HMCharacteristicTypeLogs);
    LC32_CONST_STR_INIT(HMCharacteristicTypeManufacturer);
    LC32_CONST_STR_INIT(HMCharacteristicTypeModel);
    LC32_CONST_STR_INIT(HMCharacteristicTypeMotionDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeMute);
    LC32_CONST_STR_INIT(HMCharacteristicTypeName);
    LC32_CONST_STR_INIT(HMCharacteristicTypeNightVision);
    LC32_CONST_STR_INIT(HMCharacteristicTypeNitrogenDioxideDensity);
    LC32_CONST_STR_INIT(HMCharacteristicTypeObstructionDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeOccupancyDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeOpticalZoom);
    LC32_CONST_STR_INIT(HMCharacteristicTypeOutletInUse);
    LC32_CONST_STR_INIT(HMCharacteristicTypeOutputState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeOzoneDensity);
    LC32_CONST_STR_INIT(HMCharacteristicTypePM10Density);
    LC32_CONST_STR_INIT(HMCharacteristicTypePM2_5Density);
    LC32_CONST_STR_INIT(HMCharacteristicTypePositionState);
    LC32_CONST_STR_INIT(HMCharacteristicTypePowerState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeRotationDirection);
    LC32_CONST_STR_INIT(HMCharacteristicTypeRotationSpeed);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSaturation);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSecuritySystemAlarmType);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSelectedStreamConfiguration);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSerialNumber);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSetupStreamEndpoint);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSlatType);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSmokeDetected);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSoftwareVersion);
    LC32_CONST_STR_INIT(HMCharacteristicTypeStatusActive);
    LC32_CONST_STR_INIT(HMCharacteristicTypeStatusFault);
    LC32_CONST_STR_INIT(HMCharacteristicTypeStatusJammed);
    LC32_CONST_STR_INIT(HMCharacteristicTypeStatusLowBattery);
    LC32_CONST_STR_INIT(HMCharacteristicTypeStatusTampered);
    LC32_CONST_STR_INIT(HMCharacteristicTypeStreamingStatus);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSulphurDioxideDensity);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSupportedAudioStreamConfiguration);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSupportedRTPConfiguration);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSupportedVideoStreamConfiguration);
    LC32_CONST_STR_INIT(HMCharacteristicTypeSwingMode);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetAirPurifierState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetDoorState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetFanState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetHeaterCoolerState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetHeatingCooling);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetHorizontalTilt);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetHumidifierDehumidifierState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetLockMechanismState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetPosition);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetRelativeHumidity);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetSecuritySystemState);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetTemperature);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetTilt);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTargetVerticalTilt);
    LC32_CONST_STR_INIT(HMCharacteristicTypeTemperatureUnits);
    LC32_CONST_STR_INIT(HMCharacteristicTypeVersion);
    LC32_CONST_STR_INIT(HMCharacteristicTypeVolatileOrganicCompoundDensity);
    LC32_CONST_STR_INIT(HMCharacteristicTypeVolume);
    LC32_CONST_STR_INIT(HMCharacteristicTypeWaterLevel);
    LC32_CONST_STR_INIT(HMCharacteristicValueKeyPath);
    LC32_CONST_STR_INIT(HMErrorDomain);
    LC32_CONST_STR_INIT(HMServiceTypeAccessoryInformation);
    LC32_CONST_STR_INIT(HMServiceTypeAirPurifier);
    LC32_CONST_STR_INIT(HMServiceTypeAirQualitySensor);
    LC32_CONST_STR_INIT(HMServiceTypeBattery);
    LC32_CONST_STR_INIT(HMServiceTypeCameraControl);
    LC32_CONST_STR_INIT(HMServiceTypeCameraRTPStreamManagement);
    LC32_CONST_STR_INIT(HMServiceTypeCarbonDioxideSensor);
    LC32_CONST_STR_INIT(HMServiceTypeCarbonMonoxideSensor);
    LC32_CONST_STR_INIT(HMServiceTypeContactSensor);
    LC32_CONST_STR_INIT(HMServiceTypeDoor);
    LC32_CONST_STR_INIT(HMServiceTypeDoorbell);
    LC32_CONST_STR_INIT(HMServiceTypeFan);
    LC32_CONST_STR_INIT(HMServiceTypeFilterMaintenance);
    LC32_CONST_STR_INIT(HMServiceTypeGarageDoorOpener);
    LC32_CONST_STR_INIT(HMServiceTypeHeaterCooler);
    LC32_CONST_STR_INIT(HMServiceTypeHumidifierDehumidifier);
    LC32_CONST_STR_INIT(HMServiceTypeHumiditySensor);
    LC32_CONST_STR_INIT(HMServiceTypeLabel);
    LC32_CONST_STR_INIT(HMServiceTypeLeakSensor);
    LC32_CONST_STR_INIT(HMServiceTypeLightSensor);
    LC32_CONST_STR_INIT(HMServiceTypeLightbulb);
    LC32_CONST_STR_INIT(HMServiceTypeLockManagement);
    LC32_CONST_STR_INIT(HMServiceTypeLockMechanism);
    LC32_CONST_STR_INIT(HMServiceTypeMicrophone);
    LC32_CONST_STR_INIT(HMServiceTypeMotionSensor);
    LC32_CONST_STR_INIT(HMServiceTypeOccupancySensor);
    LC32_CONST_STR_INIT(HMServiceTypeOutlet);
    LC32_CONST_STR_INIT(HMServiceTypeSecuritySystem);
    LC32_CONST_STR_INIT(HMServiceTypeSlats);
    LC32_CONST_STR_INIT(HMServiceTypeSmokeSensor);
    LC32_CONST_STR_INIT(HMServiceTypeSpeaker);
    LC32_CONST_STR_INIT(HMServiceTypeStatefulProgrammableSwitch);
    LC32_CONST_STR_INIT(HMServiceTypeStatelessProgrammableSwitch);
    LC32_CONST_STR_INIT(HMServiceTypeSwitch);
    LC32_CONST_STR_INIT(HMServiceTypeTemperatureSensor);
    LC32_CONST_STR_INIT(HMServiceTypeThermostat);
    LC32_CONST_STR_INIT(HMServiceTypeVentilationFan);
    LC32_CONST_STR_INIT(HMServiceTypeWindow);
    LC32_CONST_STR_INIT(HMServiceTypeWindowCovering);
    LC32_CONST_STR_INIT(HMSignificantEventSunrise);
    LC32_CONST_STR_INIT(HMSignificantEventSunset);
    LC32_CONST_STR_INIT(HMUserFailedAccessoriesKey);
}

#pragma clang diagnostic pop
