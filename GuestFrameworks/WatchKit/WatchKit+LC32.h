#import <WatchKit/WatchKit.h>

// The iOS-facing WatchKit umbrella hides these watchOS-only declarations even
// though the iOS 10 framework exports the classes used by the captured shims.
#import <WatchKit/WKAlertAction.h>
#import <WatchKit/WKExtension.h>
#import <WatchKit/WKAudioFileAsset.h>
#import <WatchKit/WKAudioFilePlayer.h>
#import <WatchKit/WKAudioFilePlayerItem.h>
#import <WatchKit/WKInterfaceActivityRing.h>
#import <WatchKit/WKInterfaceMovie.h>
#import <WatchKit/WKInterfaceInlineMovie.h>
#import <WatchKit/WKInterfaceSKScene.h>
#import <WatchKit/WKInterfaceSCNScene.h>
#import <WatchKit/WKInterfaceHMCamera.h>
#import <WatchKit/WKInterfacePicker.h>
#import <WatchKit/WKAccessibility.h>
#import <WatchKit/WKGestureRecognizer.h>
#import <WatchKit/WKCrownSequencer.h>
#import <WatchKit/WKBackgroundTask.h>
