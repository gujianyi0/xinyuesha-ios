// SPDX-License-Identifier: GPL-3.0-or-later
#import "../../src/platform/iosbackgroundpresentation.h"

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
  NSAssert(!self.presentation.window, @"Old picker window leaked");
  PHPickerConfiguration *configuration = fkBackgroundPickerConfiguration(false);
  NSAssert(configuration.selectionLimit == 1, @"Only one background may be selected");
  PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
  picker.delegate = self;
  self.presentation = [[FKBackgroundPresentation alloc] init];
  NSAssert([self.presentation present:picker fromWindow:self.view.window], @"Picker failed to present");
  // This is the actual production presenter, not a mock PhotosUI screen.
  NSAssert(self.presentation.window != self.view.window, @"Picker shares the game window");
  NSAssert(CATransform3DIsIdentity(self.presentation.window.layer.sublayerTransform), @"Picker is transformed");
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  self.callbacks++;
  void (^finish)(BOOL) = ^(BOOL selected) {
    NSString *message = [NSString stringWithFormat:@"%@ %ld", selected ? @"Selected" : @"Cancelled", (long)self.callbacks];
    [self.presentation close:^{
    NSAssert(!self.presentation.window, @"Picker window not released");
    NSAssert(self.view.window.isKeyWindow, @"Game window not restored");
    self.result.text = message;
    }];
  };
  if (results.count) [self.presentation confirmSelection:finish];
  else finish(NO);
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
