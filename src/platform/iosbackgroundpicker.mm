// SPDX-License-Identifier: GPL-3.0-or-later
#include "iosbackgroundpicker.h"
#include <QStandardPaths>
#include <QUuid>
#include <utility>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

@interface FKBackgroundPickerDelegate : NSObject <PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate> {
@public
  std::function<void(QUrl, QString)> completion;
  QString outputPath;
}
- (void)cancelPending;
@end

@implementation FKBackgroundPickerDelegate
- (void)cancelPending {
  auto done = std::exchange(completion, {});
  if (done) done({}, {});
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller {
  [self cancelPending];
}
- (void)dealloc {
  // Programmatic/system dismissal need not invoke the picker delegate. Release
  // the backend's busy flag even on that path, without retaining the controller.
  auto done = std::exchange(completion, {});
  if (done) dispatch_async(dispatch_get_main_queue(), ^{
    done({}, QStringLiteral("相册已关闭，请重新选择"));
  });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  auto done = std::exchange(completion, {});
  if (!done) return;
  [picker dismissViewControllerAnimated:YES completion:nil];
  if (results.count == 0) { done({}, {}); return; }
  NSItemProvider *provider = results.firstObject.itemProvider;
  const bool movie = [provider hasItemConformingToTypeIdentifier:@"public.movie"];
  QString filePath = outputPath;
  if (movie) filePath.replace(".png", ".mov");
  const QString path = filePath;
  [provider loadFileRepresentationForTypeIdentifier:movie ? @"public.movie" : @"public.image" completionHandler:^(NSURL *url, NSError *error) {
    bool ok = false;
    if (url && !error && movie) {
      ok = [NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:path.toNSString()] error:nil];
    } else if (url && !error) {
      CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
      if (source) {
        NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
          (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
          (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@4096};
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        if (image) {
          NSMutableData *data = [NSMutableData data];
          CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nullptr);
          if (destination) {
            CGImageDestinationAddImage(destination, image, nullptr);
            if (CGImageDestinationFinalize(destination))
              ok = [data writeToFile:path.toNSString() options:NSDataWritingAtomic error:nil];
            CFRelease(destination);
          }
          CGImageRelease(image);
        }
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      done(ok ? QUrl::fromLocalFile(path) : QUrl(), ok ? QString() : QStringLiteral("无法读取所选图片，请换一张图片重试"));
    });
  }];
}
@end

void fkPickIosBackground(bool allowVideo, std::function<void(QUrl, QString)> completed) {
  // Called by QML on the GUI thread. Follow the active window's presented
  // controller; do not present through a detached Qt/native dialog controller.
  UIWindow *window = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
    for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
      if (candidate.isKeyWindow) { window = candidate; break; }
    if (window) break;
  }
  UIViewController *presenter = window.rootViewController;
  while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)
    presenter = presenter.presentedViewController;
  if (!presenter || presenter.isBeingDismissed || presenter.isBeingPresented) {
    completed({}, QStringLiteral("界面正在切换，请稍后再选图片")); return;
  }
  PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
  configuration.filter = allowVideo ? [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]] : PHPickerFilter.imagesFilter;
  configuration.selectionLimit = 1;
  PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
  FKBackgroundPickerDelegate *delegate = [[FKBackgroundPickerDelegate alloc] init];
  delegate->completion = std::move(completed);
  delegate->outputPath = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/fk-background-" + QUuid::createUuid().toString(QUuid::Id128) + ".png";
  picker.delegate = delegate;
  // PHPicker's delegate is weak; keep it for the controller's lifetime without
  // a delegate -> controller retain cycle.
  static const char ownerKey = 0;
  objc_setAssociatedObject(picker, &ownerKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [presenter presentViewController:picker animated:YES completion:nil];
  picker.presentationController.delegate = delegate;
  // A rejected presentation may not call a completion/delegate method at all.
  // A weak reference keeps this check from prolonging a dismissed picker.
  __weak PHPickerViewController *weakPicker = picker;
  dispatch_async(dispatch_get_main_queue(), ^{
    PHPickerViewController *livePicker = weakPicker;
    if (livePicker && !livePicker.presentingViewController && !livePicker.isBeingPresented)
      [delegate cancelPending];
  });
}
