#import "SpringBoard.h"

NSString *kLC32ShareLogShortcutItemType = @"com.kdt.LiveExec32.shareLog";

BOOL LC32HandleShortcut(SBSApplicationShortcutItem *item, SBIconView *iconView) {
    if (![item.type isEqualToString:kLC32ShareLogShortcutItemType]) {
        return NO;
    }
    NSArray *activityItems = @[[NSURL fileURLWithPath:item.userInfo[@"URL"]]];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:nil];
    if (activityVC.popoverPresentationController) {
        activityVC.popoverPresentationController.sourceView = iconView;
        activityVC.popoverPresentationController.sourceRect = iconView.bounds;
    }
    [iconView._viewControllerForAncestor presentViewController:activityVC animated:YES completion:nil];
    return YES;
}

%group LC32SpringBoardAppShortcuts_iOS13
%hook SBIconView
- (NSArray *)applicationShortcutItems {
    NSArray *orig = %orig;
    if (![self.icon isKindOfClass:%c(SBApplicationIcon)]) return orig;
    // filter out apps not having LiveExec32.log in its Documents dir, including the rest 64bit apps
    NSURL *logURL = [self.icon.application.info.dataContainerURL URLByAppendingPathComponent:@"Documents/LiveExec32.log"];
    if (![logURL checkResourceIsReachableAndReturnError:nil]) return orig;
    
    SBSApplicationShortcutItem *shareLogItem = [%c(SBSApplicationShortcutItem) new];
    shareLogItem.localizedTitle = @"Share LiveExec32.log";
    shareLogItem.icon = [[%c(SBSApplicationShortcutSystemIcon) alloc] initWithSystemImageName:@"ant.fill"];
    shareLogItem.type = kLC32ShareLogShortcutItemType;
    shareLogItem.bundleIdentifierToLaunch = nil;
    shareLogItem.userInfo = @{@"URL": logURL.path};
    return [orig arrayByAddingObject:shareLogItem];
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
    if (!LC32HandleShortcut(item, iconView)) %orig;
}
%end

%hook SBHIconViewApplicationShortcutsContextMenuProvider
+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
    if (!LC32HandleShortcut(item, iconView)) %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *processName = NSProcessInfo.processInfo.processName;
        if([processName isEqualToString:@"SpringBoard"]) {
            %init(LC32SpringBoardAppShortcuts_iOS13);
        }
    }
}
