// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <dispatch/dispatch.h>

// Small local lifecycle trace for failures that only reproduce in the full
// game on a physical iPhone. No photo names, paths, account or image data.
static inline void fkBackgroundTrace(NSString *event, NSString *detail = nil) {
  NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  if (!docs) return;
  NSString *dir = [docs stringByAppendingPathComponent:@"FreeKill/assets"];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *path = [dir stringByAppendingPathComponent:@"background-picker.log"];
  NSData *line = [[NSString stringWithFormat:@"%@ %@ %@\n", NSDate.date, event, detail ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
  if (!attrs || [attrs fileSize] > 64 * 1024) { [line writeToFile:path atomically:YES]; return; }
  NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
  [file seekToEndOfFile]; [file writeData:line]; [file closeFile];
}

// Present from the existing game window, as Qt's own iOS file-dialog helper
// does. A second key UIWindow competes with Qt activation and keyboard window
// levels. Never change PhotosUI's system-owned view hierarchy or transforms.
@interface FKBackgroundPresentation : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, strong) UIViewController *ownedController;
- (BOOL)present:(PHPickerViewController *)picker fromWindow:(UIWindow *)window;
- (void)close:(void (^)(void))finished;
@end

@implementation FKBackgroundPresentation
- (BOOL)present:(PHPickerViewController *)picker fromWindow:(UIWindow *)window {
  NSAssert(NSThread.isMainThread, @"PhotosUI must be presented on the main thread");
  if (!window || window.hidden || self.ownedController) return NO;
  UIViewController *host = window.rootViewController;
  while (host.presentedViewController && !host.presentedViewController.isBeingDismissed)
    host = host.presentedViewController;
  if (!host.view.window || host.isBeingDismissed || host.isBeingPresented || host.presentedViewController) return NO;
  self.window = window;
  self.host = host;
  self.ownedController = picker;
  fkBackgroundTrace(@"present-request", NSStringFromClass(host.class));
  [window endEditing:YES];
  // FullScreen removes Qt's view from its window during presentation. Keep the
  // original render/input surface attached throughout the native modal instead.
  picker.modalPresentationStyle = UIModalPresentationOverFullScreen;
  picker.modalInPresentation = YES;
  [host presentViewController:picker animated:YES completion:^{
    fkBackgroundTrace(@"present-completed", [NSString stringWithFormat:@"picker-attached=%d game-attached=%d",
      picker.viewIfLoaded.window != nil, host.viewIfLoaded.window != nil]);
  }];
  // UIKit establishes presentation relationships during the transition. Neither
  // an early presentingViewController nor a temporarily detached view is proof
  // of failure. Never synthesize Cancel from a startup snapshot or timer.
  // A later explicit user retry can recover a genuinely closed session.
  return YES;
}
- (void)close:(void (^)(void))finished {
  NSAssert(NSThread.isMainThread, @"PhotosUI must be dismissed on the main thread");
  UIViewController *owned = self.ownedController;
  fkBackgroundTrace(@"close-owned", owned ? NSStringFromClass(owned.class) : @"nil");
  void (^cleanup)(void) = ^{
    self.ownedController = nil;
    self.host = nil;
    self.window = nil;
    if (finished) finished();
  };
  // Dismiss only this session's controller; keep the game window and unrelated
  // system dialogs' root controllers, visibility and key-window state intact.
  if (owned.presentingViewController) {
    [owned dismissViewControllerAnimated:NO completion:nil];
    fkBackgroundTrace(@"dismiss-returned");
  }
  cleanup();
}
@end

static inline PHPickerConfiguration *fkBackgroundPickerConfiguration(bool allowVideo) {
  PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
  configuration.filter = allowVideo
    ? [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]]
    : PHPickerFilter.imagesFilter;
  configuration.selectionLimit = 1;
  // iOS 16/17 single selection finishes immediately. Confirm in the session.
  return configuration;
}
