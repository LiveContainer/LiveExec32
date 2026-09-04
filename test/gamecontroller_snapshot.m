#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include <string.h>

int main(void) {
    @autoreleasepool {
        GCGamepadSnapShotDataV100 gamepad = {0};
        gamepad.dpadX = 0.25f;
        gamepad.buttonA = 0.75f;
        NSData *gamepadData = NSDataFromGCGamepadSnapShotDataV100(&gamepad);
        GCGamepadSnapShotDataV100 decodedGamepad = {0};
        if(!gamepadData ||
           !GCGamepadSnapShotDataV100FromNSData(
                &decodedGamepad, gamepadData) ||
           decodedGamepad.version != 0x0100 ||
           decodedGamepad.size != sizeof(decodedGamepad) ||
           decodedGamepad.dpadX != gamepad.dpadX ||
           decodedGamepad.buttonA != gamepad.buttonA) return 1;

        GCExtendedGamepadSnapShotDataV100 extended = {0};
        extended.leftThumbstickX = -0.5f;
        extended.rightTrigger = 1.0f;
        NSData *extendedData =
            NSDataFromGCExtendedGamepadSnapShotDataV100(&extended);
        GCExtendedGamepadSnapShotDataV100 decodedExtended = {0};
        if(!extendedData ||
           !GCExtendedGamepadSnapShotDataV100FromNSData(
                &decodedExtended, extendedData) ||
           decodedExtended.version != 0x0100 ||
           decodedExtended.size != sizeof(decodedExtended) ||
           decodedExtended.leftThumbstickX != extended.leftThumbstickX ||
           decodedExtended.rightTrigger != extended.rightTrigger) return 2;

        GCMicroGamepadSnapShotDataV100 micro = {0};
        micro.dpadY = -0.25f;
        micro.buttonX = 0.5f;
        NSData *microData = NSDataFromGCMicroGamepadSnapShotDataV100(&micro);
        GCMicroGamepadSnapShotDataV100 decodedMicro = {0};
        if(!microData ||
           !GCMicroGamepadSnapShotDataV100FromNSData(
                &decodedMicro, microData) ||
           decodedMicro.version != 0x0100 ||
           decodedMicro.size != sizeof(decodedMicro) ||
           decodedMicro.dpadY != micro.dpadY ||
           decodedMicro.buttonX != micro.buttonX) return 3;

        return GCMicroGamepadSnapShotDataV100FromNSData(NULL, microData) ||
               GCMicroGamepadSnapShotDataV100FromNSData(
                    &decodedMicro, nil) ? 4 : 0;
    }
}
