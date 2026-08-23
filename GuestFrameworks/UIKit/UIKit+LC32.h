#import <LC32/LC32.h>
#import <CoreGraphics/CoreGraphics+LC32.h>
#import <UIKit/UIKit.h>

typedef struct UIEdgeInsets_64 {
    CGFloat_64 top, left, bottom, right;
} UIEdgeInsets_64;

static inline UIEdgeInsets LC32GuestUIEdgeInsets(const UIEdgeInsets_64 host) {
    UIEdgeInsets result = {host.top, host.left, host.bottom, host.right};
    return result;
}

static inline UIEdgeInsets_64 LC32HostUIEdgeInsets(const UIEdgeInsets guest) {
    UIEdgeInsets_64 result = {guest.top, guest.left, guest.bottom, guest.right};
    return result;
}

@interface _UIAppearance : NSObject
@end

@interface UILayoutContainerView : UIView
@end
@interface UITableViewCellLayoutManager : NSObject
@end

@interface _UIMoreListTableView : UITableView
@end
@interface UIMoreListCellLayoutManager : UITableViewCellLayoutManager
@end
@interface UIMoreListController : UIViewController
@end
@interface UIMoreNavigationController : UINavigationController
@end

@interface UINibDecoder : NSObject
@end

@interface UIDeviceRGBColor : UIColor
@end
@interface UIDeviceWhiteColor : UIColor
@end
@interface UICachedDeviceWhiteColor : UIDeviceWhiteColor
@end
@interface UIDynamicColor : UIColor
@end
@interface UIDynamicSystemColor : UIDynamicColor
@end
