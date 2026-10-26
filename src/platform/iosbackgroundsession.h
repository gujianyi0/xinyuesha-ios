// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "iosbackgroundpresentation.h"
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>

@interface FKBackgroundPickerSession : NSObject <PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate> {
@public
  void (^completion)(NSURL *, NSString *);
  NSString *outputPath;
}
@property(nonatomic, strong) FKBackgroundPresentation *presentation;
- (void)cancelPending;
- (void)failPending:(NSString *)error;
@end

@implementation FKBackgroundPickerSession
- (void)cancelPending {
  [self failPending:nil];
}
- (void)failPending:(NSString *)error {
  fkBackgroundTrace(@"session-finish", error ?: @"cancel");
  auto done = completion; completion = nil;
  if (!done) return;
  [self.presentation close:^{ done(nil, error); }];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller {
  fkBackgroundTrace(@"presentation-dismissed");
  [self cancelPending];
}
- (void)dealloc {
  // Programmatic/system dismissal need not invoke the picker delegate. Release
  // the backend's busy flag even on that path, without retaining the controller.
  auto done = completion; completion = nil;
  if (done) fkBackgroundTrace(@"session-dealloc-pending");
  FKBackgroundPresentation *presentation = self.presentation;
  if (done) dispatch_async(dispatch_get_main_queue(), ^{
    [presentation close:^{ done(nil, @"相册已关闭，请重新选择"); }];
  });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  fkBackgroundTrace(@"picker-result", [NSString stringWithFormat:@"count=%lu", (unsigned long)results.count]);
  auto done = completion; completion = nil;
  if (!done) return;
  if (results.count == 0) {
    [self.presentation close:^{ done(nil, nil); }];
    return;
  }
  // Dismiss the native controller before publishing a result back into QML. File
  // decoding runs in the item-provider callback, never in a UIKit tap handler.
  FKBackgroundPresentation *presentation = self.presentation;
  NSItemProvider *provider = results.firstObject.itemProvider;
  const bool movie = [provider hasItemConformingToTypeIdentifier:@"public.movie"];
  __block NSString *path = movie ? [[outputPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"mov"] : outputPath;
  [presentation close:^{
  [provider loadFileRepresentationForTypeIdentifier:movie ? @"public.movie" : @"public.image" completionHandler:^(NSURL *url, NSError *error) {
    bool ok = false;
    if (url && !error && movie) {
      ok = [NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:path] error:nil];
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
          const CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image);
          const bool opaque = alpha == kCGImageAlphaNone || alpha == kCGImageAlphaNoneSkipFirst || alpha == kCGImageAlphaNoneSkipLast;
          if (opaque) path = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
          CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
            opaque ? CFSTR("public.jpeg") : CFSTR("public.png"), 1, nullptr);
          if (destination) {
            CGImageDestinationAddImage(destination, image, opaque ? (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@0.9} : nullptr);
            if (CGImageDestinationFinalize(destination))
              ok = [data writeToFile:path options:NSDataWritingAtomic error:nil];
            CFRelease(destination);
          }
          CGImageRelease(image);
        }
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      fkBackgroundTrace(@"import-result", ok ? @"saved" : @"failed");
      done(ok ? [NSURL fileURLWithPath:path] : nil, ok ? nil : @"无法读取所选图片，请换一张图片重试");
    });
  }];
  }];
}
@end

// Own the entire real session explicitly, including the delay before the host
// appears. Picker delegates are weak; lifetime cannot depend on presentation
// relationship getters while UIKit is still starting its transition.
static FKBackgroundPickerSession *fkActiveBackgroundSession;
static inline void fkOpenBackgroundPicker(UIWindow *window, bool allowVideo,
    void (^finished)(NSURL *, NSString *)) {
  NSCAssert(NSThread.isMainThread, @"PhotosUI session must start on main thread");
  if (!window || !window.rootViewController || window.rootViewController.isBeingDismissed || fkActiveBackgroundSession) {
    finished(nil, @"界面正在切换，请稍后再选图片"); return;
  }
  FKBackgroundPickerSession *session = [[FKBackgroundPickerSession alloc] init];
  fkActiveBackgroundSession = session;
  session->completion = ^(NSURL *url, NSString *error) {
    fkActiveBackgroundSession = nil;
    finished(url, error);
  };
  session->outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"fk-background-%@.png", NSUUID.UUID.UUIDString]];
  PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:fkBackgroundPickerConfiguration(allowVideo)];
  picker.delegate = session;
  session.presentation = [[FKBackgroundPresentation alloc] init];
  if (![session.presentation present:picker fromWindow:window]) {
    [session failPending:@"界面正在切换，请稍后再选图片"]; return;
  }
  picker.presentationController.delegate = session;
}
