// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>

// UIKit owns this window, including the search keyboard. Presenting inside Qt's
// root controller shares its keyboard scrolling/gesture handling with PhotosUI.
// Do not change PHPicker's system-owned view hierarchy, alpha or transforms.
@interface FKBackgroundPresentation : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, weak) UIWindow *previousWindow;
- (BOOL)present:(PHPickerViewController *)picker fromWindow:(UIWindow *)previous;
- (void)close:(void (^)(void))finished;
@end

@implementation FKBackgroundPresentation
- (BOOL)present:(PHPickerViewController *)picker fromWindow:(UIWindow *)previous {
  NSAssert(NSThread.isMainThread, @"PhotosUI must be presented on the main thread");
  if (!previous || self.window) return NO;
  self.previousWindow = previous;
  [previous endEditing:YES];
  // Qt 6.8 also supports apps without UIApplicationSceneManifest. Those
  // windows need the legacy initializer; do not reject a usable game window.
  UIWindow *window = previous.windowScene
    ? [[UIWindow alloc] initWithWindowScene:previous.windowScene]
    : [[UIWindow alloc] initWithFrame:previous.bounds];
  if (!previous.windowScene) window.screen = previous.screen;
  window.windowLevel = previous.windowLevel + 1;
  UIViewController *host = [[UIViewController alloc] init];
  host.view.backgroundColor = UIColor.systemBackgroundColor;
  window.rootViewController = host;
  self.window = window;
  [window makeKeyAndVisible];
  picker.modalPresentationStyle = UIModalPresentationFullScreen;
  [host presentViewController:picker animated:YES completion:nil];
  // UIKit establishes presentingViewController during its transition. A nil
  // value in this call stack is not rejection: checking it here cancels a valid
  // presentation before PhotosUI can become interactive. The caller checks on
  // the next main-loop turn and owns the asynchronous failure cleanup.
  return YES;
}
- (void)close:(void (^)(void))finished {
  NSAssert(NSThread.isMainThread, @"PhotosUI must be dismissed on the main thread");
  UIWindow *window = self.window;
  if (!window) { if (finished) finished(); return; }
  // Restore Qt only after UIKit has finished dismissing. Keeping a hidden Qt
  // keyboard/window active underneath the picker can swallow its Cancel tap.
  void (^cleanup)(void) = ^{
    BOOL restoreKey = window.isKeyWindow;
    window.hidden = YES;
    window.rootViewController = nil;
    self.window = nil;
    if (restoreKey && !self.previousWindow.hidden) [self.previousWindow makeKeyWindow];
    self.previousWindow = nil;
    if (finished) finished();
  };
  if (window.rootViewController.presentedViewController)
    [window.rootViewController dismissViewControllerAnimated:YES completion:cleanup];
  else cleanup();
}
@end

static inline PHPickerConfiguration *fkBackgroundPickerConfiguration(bool allowVideo) {
  PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
  configuration.filter = allowVideo
    ? [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]]
    : PHPickerFilter.imagesFilter;
  configuration.selectionLimit = 1;
  // Ordered selection retains PhotosUI's explicit Add/Done action even for one
  // background, rather than immediately importing when a thumbnail is tapped.
  configuration.selection = PHPickerConfigurationSelectionOrdered;
  return configuration;
}
