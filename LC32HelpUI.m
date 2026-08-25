#import <UIKit/UIKit.h>

static void LC32ShowLauncherWindow(UIWindow *window) {
    NSString *message;
    if (!getenv("LC_HOME_PATH")) {
        message = @"LiveExec32 app requires to be installed inside LiveContainer.";
    } else {
        message = @"LiveExec32 is an 32-bit emulation layer for modern iOS. "
        "To use 32-bit apps, set LiveExec32 as default and launch your app from LiveContainer.";
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]
        message:message preferredStyle:UIAlertControllerStyleAlert];
    window.rootViewController = [UIViewController new];
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:NO completion:nil];
}

API_AVAILABLE(ios(13.0))
@interface LC32HelpSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation LC32HelpSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
    (void)connectionOptions;
    if(![scene isKindOfClass:UIWindowScene.class]) return;

    self.window = [[UIWindow alloc]
        initWithWindowScene:(UIWindowScene *)scene];
    LC32ShowLauncherWindow(self.window);
}

@end

@interface LC32HelpAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation LC32HelpAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    /*
     * Do not opt the bundle into scenes in Info.plist. This executable also
     * hosts guest UIApplicationMain calls, and bundle-wide scene routing
     * would replace their application delegates. The scene delegate above is
     * ready for a future launcher-only scene configuration.
     */
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    LC32ShowLauncherWindow(self.window);
    return YES;
}


- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
    options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
    UISceneConfiguration *config = [UISceneConfiguration
        configurationWithName:@"Default Configuration"
        sessionRole:connectingSceneSession.role];
    config.delegateClass = LC32HelpSceneDelegate.class;
    return config;
}

@end

int LC32RunHelpUI(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(
            argc, argv, nil,
            NSStringFromClass(LC32HelpAppDelegate.class));
    }
}
