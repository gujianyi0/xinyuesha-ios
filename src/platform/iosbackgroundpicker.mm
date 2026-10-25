// SPDX-License-Identifier: GPL-3.0-or-later
#include "iosbackgroundpicker.h"
#include <QStandardPaths>
#include <QUuid>
#include <utility>
#include <QGuiApplication>
#include <QInputMethod>
#import "iosbackgroundpresentation.h"
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
@property(nonatomic, strong) FKBackgroundPresentation *presentation;
- (void)cancelPending;
@end

@implementation FKBackgroundPickerDelegate
- (void)cancelPending {
  auto done = std::exchange(completion, {});
  if (!done) return;
  [self.presentation close:^{ if (done) done({}, {}); }];
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
  if (results.count == 0) {
    [self.presentation close:^{ done({}, {}); }];
    return;
  }
  // Release the native window before publishing a result back into QML. File
  // decoding runs in the item-provider callback, never in a UIKit tap handler.
  FKBackgroundPresentation *presentation = self.presentation;
  NSItemProvider *provider = results.firstObject.itemProvider;
  const bool movie = [provider hasItemConformingToTypeIdentifier:@"public.movie"];
  QString filePath = outputPath;
  if (movie) filePath.replace(".png", ".mov");
  const QString path = filePath;
  [presentation close:^{
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
  }];
}
@end

void fkPickIosBackground(bool allowVideo, std::function<void(QUrl, QString)> completed) {
  // Finish Qt's current input delivery before handing focus to UIKit. In
  // particular, do not leave a QML text responder active beneath PhotosUI.
  if (QGuiApplication::inputMethod()) {
    QGuiApplication::inputMethod()->reset();
    QGuiApplication::inputMethod()->hide();
  }
  dispatch_async(dispatch_get_main_queue(), ^{
  UIWindow *window = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
    for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
      if (candidate.isKeyWindow) { window = candidate; break; }
    if (window) break;
  }
  if (!window || !window.rootViewController || window.rootViewController.isBeingDismissed) {
    completed({}, QStringLiteral("界面正在切换，请稍后再选图片")); return;
  }
  PHPickerConfiguration *configuration = fkBackgroundPickerConfiguration(allowVideo);
  PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
  FKBackgroundPickerDelegate *delegate = [[FKBackgroundPickerDelegate alloc] init];
  delegate->completion = std::move(completed);
  delegate->outputPath = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/fk-background-" + QUuid::createUuid().toString(QUuid::Id128) + ".png";
  picker.delegate = delegate;
  // PHPicker's delegate is weak; keep it for the controller's lifetime without
  // a delegate -> controller retain cycle.
  static const char ownerKey = 0;
  objc_setAssociatedObject(picker, &ownerKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  delegate.presentation = [[FKBackgroundPresentation alloc] init];
  if (![delegate.presentation present:picker fromWindow:window]) {
    [delegate cancelPending];
    return;
  }
  picker.presentationController.delegate = delegate;
  // A rejected presentation may not call a completion/delegate method at all.
  // A weak reference keeps this check from prolonging a dismissed picker.
  __weak PHPickerViewController *weakPicker = picker;
  dispatch_async(dispatch_get_main_queue(), ^{
    PHPickerViewController *livePicker = weakPicker;
    if (livePicker && !livePicker.presentingViewController && !livePicker.isBeingPresented)
      [delegate cancelPending];
  });
  });
}
