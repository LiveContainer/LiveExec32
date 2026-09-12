@import UIKit;

@interface UIView(Private)
- (UIViewController *)_viewControllerForAncestor;
@end

@interface SBApplicationInfo : NSObject
- (NSURL *)dataContainerURL;
@end

@interface SBApplication : NSObject
- (SBApplicationInfo *)info;
@end

@interface SBIcon : NSObject
@end
@interface SBApplicationIcon : SBIcon
- (SBApplication *)application;
@end

@interface SBIconView : UIView
- (SBApplicationIcon *)icon;
- (NSString *)applicationBundleIdentifier;
- (NSString *)applicationBundleIdentifierForShortcuts;
@end

@interface SBSApplicationShortcutIcon : NSObject
@end
@interface SBSApplicationShortcutSystemIcon : SBSApplicationShortcutIcon
- (instancetype)initWithSystemImageName:(NSString *)name;
@end

@interface SBSApplicationShortcutItem : NSObject
@property(nonatomic) SBSApplicationShortcutIcon *icon;
@property(nonatomic) NSString *bundleIdentifierToLaunch;
@property(nonatomic) NSString *localizedTitle;
@property(nonatomic) NSString *type;
@property(nonatomic) NSDictionary *userInfo;
@end
