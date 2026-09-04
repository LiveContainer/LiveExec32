#import <HealthKit/HealthKit.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierAppleStandHour)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierCervicalMucusQuality)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierIntermenstrualBleeding)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierMenstrualFlow)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierMindfulSession)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierOvulationTestResult)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierSexualActivity)
LC32_CONST_STR_DECL(NSString *const HKCategoryTypeIdentifierSleepAnalysis)
LC32_CONST_STR_DECL(NSString *const HKCharacteristicTypeIdentifierBiologicalSex)
LC32_CONST_STR_DECL(NSString *const HKCharacteristicTypeIdentifierBloodType)
LC32_CONST_STR_DECL(NSString *const HKCharacteristicTypeIdentifierDateOfBirth)
LC32_CONST_STR_DECL(NSString *const HKCharacteristicTypeIdentifierFitzpatrickSkinType)
LC32_CONST_STR_DECL(NSString *const HKCharacteristicTypeIdentifierWheelchairUse)
LC32_CONST_STR_DECL(NSString *const HKCorrelationTypeIdentifierBloodPressure)
LC32_CONST_STR_DECL(NSString *const HKCorrelationTypeIdentifierFood)
LC32_CONST_STR_DECL(NSString *const HKDetailedCDAValidationErrorKey)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyFirmwareVersion)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyHardwareVersion)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyLocalIdentifier)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyManufacturer)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyModel)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyName)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeySoftwareVersion)
LC32_CONST_STR_DECL(NSString *const HKDevicePropertyKeyUDIDeviceIdentifier)
LC32_CONST_STR_DECL(NSString *const HKDocumentTypeIdentifierCDA)
LC32_CONST_STR_DECL(NSString *const HKErrorDomain)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyBodyTemperatureSensorLocation)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyCoachedWorkout)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyDeviceManufacturerName)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyDeviceName)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyDeviceSerialNumber)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyDigitalSignature)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyExternalUUID)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyFoodType)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyGroupFitness)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyHeartRateSensorLocation)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyIndoorWorkout)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyLapLength)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyMenstrualCycleStart)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyReferenceRangeLowerLimit)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyReferenceRangeUpperLimit)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeySexualActivityProtectionUsed)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeySwimmingLocationType)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeySwimmingStrokeStyle)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyTimeZone)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyUDIDeviceIdentifier)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyUDIProductionIdentifier)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyWasTakenInLab)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyWasUserEntered)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyWeatherCondition)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyWeatherHumidity)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyWeatherTemperature)
LC32_CONST_STR_DECL(NSString *const HKMetadataKeyWorkoutBrandName)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathCDAAuthorName)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathCDACustodianName)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathCDAPatientName)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathCDATitle)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathCategoryValue)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathCorrelation)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathDateComponents)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathDevice)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathEndDate)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathMetadata)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathQuantity)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathSource)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathSourceRevision)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathStartDate)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathUUID)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathWorkout)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathWorkoutDuration)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathWorkoutTotalDistance)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathWorkoutTotalEnergyBurned)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathWorkoutTotalSwimmingStrokeCount)
LC32_CONST_STR_DECL(NSString *const HKPredicateKeyPathWorkoutType)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierActiveEnergyBurned)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierAppleExerciseTime)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBasalBodyTemperature)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBasalEnergyBurned)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBloodAlcoholContent)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBloodGlucose)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBloodPressureDiastolic)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBloodPressureSystolic)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBodyFatPercentage)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBodyMass)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBodyMassIndex)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierBodyTemperature)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryBiotin)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryCaffeine)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryCalcium)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryCarbohydrates)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryChloride)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryCholesterol)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryChromium)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryCopper)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryEnergyConsumed)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryFatMonounsaturated)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryFatPolyunsaturated)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryFatSaturated)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryFatTotal)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryFiber)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryFolate)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryIodine)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryIron)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryMagnesium)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryManganese)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryMolybdenum)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryNiacin)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryPantothenicAcid)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryPhosphorus)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryPotassium)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryProtein)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryRiboflavin)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietarySelenium)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietarySodium)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietarySugar)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryThiamin)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminA)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminB12)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminB6)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminC)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminD)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminE)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryVitaminK)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryWater)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDietaryZinc)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDistanceCycling)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDistanceSwimming)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDistanceWalkingRunning)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierDistanceWheelchair)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierElectrodermalActivity)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierFlightsClimbed)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierForcedExpiratoryVolume1)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierForcedVitalCapacity)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierHeartRate)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierHeight)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierInhalerUsage)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierLeanBodyMass)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierNikeFuel)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierNumberOfTimesFallen)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierOxygenSaturation)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierPeakExpiratoryFlowRate)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierPeripheralPerfusionIndex)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierPushCount)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierRespiratoryRate)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierStepCount)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierSwimmingStrokeCount)
LC32_CONST_STR_DECL(NSString *const HKQuantityTypeIdentifierUVExposure)
LC32_CONST_STR_DECL(NSString *const HKSampleSortIdentifierEndDate)
LC32_CONST_STR_DECL(NSString *const HKSampleSortIdentifierStartDate)
LC32_CONST_STR_DECL(NSString *const HKUserPreferencesDidChangeNotification)
LC32_CONST_STR_DECL(NSString *const HKWorkoutSortIdentifierDuration)
LC32_CONST_STR_DECL(NSString *const HKWorkoutSortIdentifierTotalDistance)
LC32_CONST_STR_DECL(NSString *const HKWorkoutSortIdentifierTotalEnergyBurned)
LC32_CONST_STR_DECL(NSString *const HKWorkoutSortIdentifierTotalSwimmingStrokeCount)
LC32_CONST_STR_DECL(NSString *const HKWorkoutTypeIdentifier)

__attribute__((constructor)) static void LC32InitializeHealthKitConstants(void) {
    LC32LoadHostFramework("HealthKit");
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierAppleStandHour);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierCervicalMucusQuality);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierIntermenstrualBleeding);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierMenstrualFlow);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierMindfulSession);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierOvulationTestResult);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierSexualActivity);
    LC32_CONST_STR_INIT(HKCategoryTypeIdentifierSleepAnalysis);
    LC32_CONST_STR_INIT(HKCharacteristicTypeIdentifierBiologicalSex);
    LC32_CONST_STR_INIT(HKCharacteristicTypeIdentifierBloodType);
    LC32_CONST_STR_INIT(HKCharacteristicTypeIdentifierDateOfBirth);
    LC32_CONST_STR_INIT(HKCharacteristicTypeIdentifierFitzpatrickSkinType);
    LC32_CONST_STR_INIT(HKCharacteristicTypeIdentifierWheelchairUse);
    LC32_CONST_STR_INIT(HKCorrelationTypeIdentifierBloodPressure);
    LC32_CONST_STR_INIT(HKCorrelationTypeIdentifierFood);
    LC32_CONST_STR_INIT(HKDetailedCDAValidationErrorKey);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyFirmwareVersion);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyHardwareVersion);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyLocalIdentifier);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyManufacturer);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyModel);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyName);
    LC32_CONST_STR_INIT(HKDevicePropertyKeySoftwareVersion);
    LC32_CONST_STR_INIT(HKDevicePropertyKeyUDIDeviceIdentifier);
    LC32_CONST_STR_INIT(HKDocumentTypeIdentifierCDA);
    LC32_CONST_STR_INIT(HKErrorDomain);
    LC32_CONST_STR_INIT(HKMetadataKeyBodyTemperatureSensorLocation);
    LC32_CONST_STR_INIT(HKMetadataKeyCoachedWorkout);
    LC32_CONST_STR_INIT(HKMetadataKeyDeviceManufacturerName);
    LC32_CONST_STR_INIT(HKMetadataKeyDeviceName);
    LC32_CONST_STR_INIT(HKMetadataKeyDeviceSerialNumber);
    LC32_CONST_STR_INIT(HKMetadataKeyDigitalSignature);
    LC32_CONST_STR_INIT(HKMetadataKeyExternalUUID);
    LC32_CONST_STR_INIT(HKMetadataKeyFoodType);
    LC32_CONST_STR_INIT(HKMetadataKeyGroupFitness);
    LC32_CONST_STR_INIT(HKMetadataKeyHeartRateSensorLocation);
    LC32_CONST_STR_INIT(HKMetadataKeyIndoorWorkout);
    LC32_CONST_STR_INIT(HKMetadataKeyLapLength);
    LC32_CONST_STR_INIT(HKMetadataKeyMenstrualCycleStart);
    LC32_CONST_STR_INIT(HKMetadataKeyReferenceRangeLowerLimit);
    LC32_CONST_STR_INIT(HKMetadataKeyReferenceRangeUpperLimit);
    LC32_CONST_STR_INIT(HKMetadataKeySexualActivityProtectionUsed);
    LC32_CONST_STR_INIT(HKMetadataKeySwimmingLocationType);
    LC32_CONST_STR_INIT(HKMetadataKeySwimmingStrokeStyle);
    LC32_CONST_STR_INIT(HKMetadataKeyTimeZone);
    LC32_CONST_STR_INIT(HKMetadataKeyUDIDeviceIdentifier);
    LC32_CONST_STR_INIT(HKMetadataKeyUDIProductionIdentifier);
    LC32_CONST_STR_INIT(HKMetadataKeyWasTakenInLab);
    LC32_CONST_STR_INIT(HKMetadataKeyWasUserEntered);
    LC32_CONST_STR_INIT(HKMetadataKeyWeatherCondition);
    LC32_CONST_STR_INIT(HKMetadataKeyWeatherHumidity);
    LC32_CONST_STR_INIT(HKMetadataKeyWeatherTemperature);
    LC32_CONST_STR_INIT(HKMetadataKeyWorkoutBrandName);
    LC32_CONST_STR_INIT(HKPredicateKeyPathCDAAuthorName);
    LC32_CONST_STR_INIT(HKPredicateKeyPathCDACustodianName);
    LC32_CONST_STR_INIT(HKPredicateKeyPathCDAPatientName);
    LC32_CONST_STR_INIT(HKPredicateKeyPathCDATitle);
    LC32_CONST_STR_INIT(HKPredicateKeyPathCategoryValue);
    LC32_CONST_STR_INIT(HKPredicateKeyPathCorrelation);
    LC32_CONST_STR_INIT(HKPredicateKeyPathDateComponents);
    LC32_CONST_STR_INIT(HKPredicateKeyPathDevice);
    LC32_CONST_STR_INIT(HKPredicateKeyPathEndDate);
    LC32_CONST_STR_INIT(HKPredicateKeyPathMetadata);
    LC32_CONST_STR_INIT(HKPredicateKeyPathQuantity);
    LC32_CONST_STR_INIT(HKPredicateKeyPathSource);
    LC32_CONST_STR_INIT(HKPredicateKeyPathSourceRevision);
    LC32_CONST_STR_INIT(HKPredicateKeyPathStartDate);
    LC32_CONST_STR_INIT(HKPredicateKeyPathUUID);
    LC32_CONST_STR_INIT(HKPredicateKeyPathWorkout);
    LC32_CONST_STR_INIT(HKPredicateKeyPathWorkoutDuration);
    LC32_CONST_STR_INIT(HKPredicateKeyPathWorkoutTotalDistance);
    LC32_CONST_STR_INIT(HKPredicateKeyPathWorkoutTotalEnergyBurned);
    LC32_CONST_STR_INIT(HKPredicateKeyPathWorkoutTotalSwimmingStrokeCount);
    LC32_CONST_STR_INIT(HKPredicateKeyPathWorkoutType);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierActiveEnergyBurned);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierAppleExerciseTime);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBasalBodyTemperature);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBasalEnergyBurned);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBloodAlcoholContent);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBloodGlucose);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBloodPressureDiastolic);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBloodPressureSystolic);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBodyFatPercentage);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBodyMass);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBodyMassIndex);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierBodyTemperature);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryBiotin);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryCaffeine);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryCalcium);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryCarbohydrates);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryChloride);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryCholesterol);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryChromium);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryCopper);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryEnergyConsumed);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryFatMonounsaturated);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryFatPolyunsaturated);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryFatSaturated);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryFatTotal);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryFiber);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryFolate);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryIodine);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryIron);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryMagnesium);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryManganese);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryMolybdenum);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryNiacin);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryPantothenicAcid);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryPhosphorus);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryPotassium);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryProtein);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryRiboflavin);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietarySelenium);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietarySodium);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietarySugar);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryThiamin);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminA);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminB12);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminB6);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminC);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminD);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminE);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryVitaminK);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryWater);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDietaryZinc);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDistanceCycling);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDistanceSwimming);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDistanceWalkingRunning);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierDistanceWheelchair);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierElectrodermalActivity);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierFlightsClimbed);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierForcedExpiratoryVolume1);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierForcedVitalCapacity);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierHeartRate);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierHeight);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierInhalerUsage);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierLeanBodyMass);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierNikeFuel);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierNumberOfTimesFallen);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierOxygenSaturation);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierPeakExpiratoryFlowRate);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierPeripheralPerfusionIndex);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierPushCount);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierRespiratoryRate);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierStepCount);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierSwimmingStrokeCount);
    LC32_CONST_STR_INIT(HKQuantityTypeIdentifierUVExposure);
    LC32_CONST_STR_INIT(HKSampleSortIdentifierEndDate);
    LC32_CONST_STR_INIT(HKSampleSortIdentifierStartDate);
    LC32_CONST_STR_INIT(HKUserPreferencesDidChangeNotification);
    LC32_CONST_STR_INIT(HKWorkoutSortIdentifierDuration);
    LC32_CONST_STR_INIT(HKWorkoutSortIdentifierTotalDistance);
    LC32_CONST_STR_INIT(HKWorkoutSortIdentifierTotalEnergyBurned);
    LC32_CONST_STR_INIT(HKWorkoutSortIdentifierTotalSwimmingStrokeCount);
    LC32_CONST_STR_INIT(HKWorkoutTypeIdentifier);
}

#pragma clang diagnostic pop
