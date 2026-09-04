#import <Intents/Intents.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

double IntentsVersionNumber = 1.0;
const unsigned char IntentsVersionString[] =
    "@(#)PROGRAM:Intents  PROJECT:Intents-1\n";

/* Bind guest proxies to the native framework's canonical object constants. */
#define LC32_INTENTS_OBJECT_CONSTANTS(X) \
    X(INCancelWorkoutIntentIdentifier) \
    X(INEndWorkoutIntentIdentifier) \
    X(INGetRideStatusIntentIdentifier) \
    X(INIntentErrorDomain) \
    X(INListRideOptionsIntentIdentifier) \
    X(INPauseWorkoutIntentIdentifier) \
    X(INPersonHandleLabelHome) \
    X(INPersonHandleLabelHomeFax) \
    X(INPersonHandleLabelMain) \
    X(INPersonHandleLabelMobile) \
    X(INPersonHandleLabelOther) \
    X(INPersonHandleLabelPager) \
    X(INPersonHandleLabelWork) \
    X(INPersonHandleLabelWorkFax) \
    X(INPersonHandleLabeliPhone) \
    X(INPersonRelationshipAssistant) \
    X(INPersonRelationshipBrother) \
    X(INPersonRelationshipChild) \
    X(INPersonRelationshipFather) \
    X(INPersonRelationshipFriend) \
    X(INPersonRelationshipManager) \
    X(INPersonRelationshipMother) \
    X(INPersonRelationshipParent) \
    X(INPersonRelationshipPartner) \
    X(INPersonRelationshipSister) \
    X(INPersonRelationshipSpouse) \
    X(INRequestPaymentIntentIdentifier) \
    X(INRequestRideIntentIdentifier) \
    X(INResumeWorkoutIntentIdentifier) \
    X(INSaveProfileInCarIntentIdentifier) \
    X(INSearchCallHistoryIntentIdentifier) \
    X(INSearchForMessagesIntentIdentifier) \
    X(INSearchForPhotosIntentIdentifier) \
    X(INSendMessageIntentIdentifier) \
    X(INSendPaymentIntentIdentifier) \
    X(INSetAudioSourceInCarIntentIdentifier) \
    X(INSetClimateSettingsInCarIntentIdentifier) \
    X(INSetDefrosterSettingsInCarIntentIdentifier) \
    X(INSetMessageAttributeIntentIdentifier) \
    X(INSetProfileInCarIntentIdentifier) \
    X(INSetRadioStationIntentIdentifier) \
    X(INSetSeatSettingsInCarIntentIdentifier) \
    X(INStartAudioCallIntentIdentifier) \
    X(INStartPhotoPlaybackIntentIdentifier) \
    X(INStartVideoCallIntentIdentifier) \
    X(INStartWorkoutIntentIdentifier) \
    X(INWorkoutNameIdentifierCrosstraining) \
    X(INWorkoutNameIdentifierCycle) \
    X(INWorkoutNameIdentifierDance) \
    X(INWorkoutNameIdentifierElliptical) \
    X(INWorkoutNameIdentifierExercise) \
    X(INWorkoutNameIdentifierIndoorcycle) \
    X(INWorkoutNameIdentifierIndoorrun) \
    X(INWorkoutNameIdentifierIndoorwalk) \
    X(INWorkoutNameIdentifierMove) \
    X(INWorkoutNameIdentifierOther) \
    X(INWorkoutNameIdentifierRower) \
    X(INWorkoutNameIdentifierRun) \
    X(INWorkoutNameIdentifierSit) \
    X(INWorkoutNameIdentifierStairs) \
    X(INWorkoutNameIdentifierStand) \
    X(INWorkoutNameIdentifierSteps) \
    X(INWorkoutNameIdentifierWalk) \
    X(INWorkoutNameIdentifierYoga)

#define LC32_DECLARE_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_INTENTS_OBJECT_CONSTANTS(LC32_DECLARE_OBJECT_CONSTANT)
#undef LC32_DECLARE_OBJECT_CONSTANT

__attribute__((constructor))
static void LC32InitializeIntentsObjectConstants(void) {
    LC32LoadHostFramework("Intents");
#define LC32_INITIALIZE_OBJECT_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_INTENTS_OBJECT_CONSTANTS(LC32_INITIALIZE_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_OBJECT_CONSTANT
}

#undef LC32_INTENTS_OBJECT_CONSTANTS
