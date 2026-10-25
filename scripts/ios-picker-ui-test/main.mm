// SPDX-License-Identifier: GPL-3.0-or-later
#import "../../src/platform/iosbackgroundsession.h"

@interface PickerController : UIViewController <PHPickerViewControllerDelegate>
@property(nonatomic, strong) FKBackgroundPresentation *presentation;
@property(nonatomic, strong) UILabel *result;
@property(nonatomic) NSInteger callbacks;
@end
@implementation PickerController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.whiteColor;
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:@"Choose background" forState:UIControlStateNormal];
  button.frame = CGRectMake(40, 40, 250, 50);
  [button addTarget:self action:@selector(choose) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:button];
  self.result = [[UILabel alloc] initWithFrame:CGRectMake(40, 120, 700, 60)];
  self.result.accessibilityIdentifier = @"result";
  self.result.text = @"Ready";
  [self.view addSubview:self.result];
}
- (void)choose {
  NSAssert(!fkActiveBackgroundSession, @"Old picker session leaked");
  fkOpenBackgroundPicker(self.view.window, false, ^(NSURL *url, NSString *error) {
    self.callbacks++;
    NSAssert(!error, @"Unexpected session error: %@", error);
    NSAssert(!fkActiveBackgroundSession, @"Session ownership not released");
    NSAssert(self.view.window.isKeyWindow, @"Game window not restored");
    if (url) {
      NSAssert([NSFileManager.defaultManager fileExistsAtPath:url.path], @"Selected image not decoded");
      [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
    self.result.text = [NSString stringWithFormat:@"%@ %ld", url ? @"Selected" : @"Cancelled", (long)self.callbacks];
  });
}

@end

@interface PickerScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation PickerScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  self.window.rootViewController = [[PickerController alloc] init];
  [self.window makeKeyAndVisible];
}
@end
@interface PickerApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation PickerApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  // Match the shipped Qt app's Info.plist: no Scene manifest/delegate.
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[PickerController alloc] init];
  [self.window makeKeyAndVisible];
  return YES;
}
@end
int main(int argc, char **argv) {
  @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PickerApp.class)); }
}
