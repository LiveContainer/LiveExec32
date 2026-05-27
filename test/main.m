#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <LC32/LC32.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

// My test app code
@interface ViewController : UIViewController
@end
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.grayColor;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(100, 100, 200, 50)];
    label.text = @"Hello world from 32bit!!!";
    [self.view addSubview:label];

    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(100, 200, 200, 100)];
    [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button setTitle:@"Click this" forState:UIControlStateNormal];
    [self.view addSubview:button];
}

- (void)buttonTapped:(UIButton *)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Hello world" message:@"32bit dialog is here lmao" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] init];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[ViewController alloc] init]];
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)applicationWillResignActive:(UIApplication *)application {}
- (void)applicationDidEnterBackground:(UIApplication *)application {}
- (void)applicationWillEnterForeground:(UIApplication *)application {}
- (void)applicationDidBecomeActive:(UIApplication *)application {}
- (void)applicationWillTerminate:(UIApplication *)application {}
@end

// NSLog doesn't work yet
#define printObjC(...) printf("%s\n", [NSString stringWithFormat:__VA_ARGS__].UTF8String)

const char *lzma_version_string();

int main(int argc, char **argv) {
  printf("Hello world from 32bit!\n");
  printf("LZMA ver %s\n", lzma_version_string());

  UIView *testView = [UIView new];
  CGRect frame = testView.frame;
  printf("Before: %f, %f, %f, %f\n", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
  testView.frame = CGRectMake(12.233, 25.525, 4056.7, 801.2);
  frame = testView.frame;
  printf("After: %f, %f, %f, %f\n", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);

  //ViewController *test = [ViewController new];
  //ensure no objects were duplicated
  //assert(LC32HostToGuestObject([test host_self]) == test);

  //printObjC(@"ClassName of constant %@", cls.class);
  return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
}
