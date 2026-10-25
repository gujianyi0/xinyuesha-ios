// SPDX-License-Identifier: GPL-3.0-or-later
#include "iosbackgroundpicker.h"
#include <QGuiApplication>
#include <QInputMethod>
#import "iosbackgroundsession.h"
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>

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
  if (!window) {
    for (UIWindow *candidate in UIApplication.sharedApplication.windows)
      if (candidate.isKeyWindow && candidate.rootViewController) { window = candidate; break; }
  }
  if (!window || !window.rootViewController || window.rootViewController.isBeingDismissed) {
    completed({}, QStringLiteral("界面正在切换，请稍后再选图片")); return;
  }
  fkOpenBackgroundPicker(window, allowVideo, ^(NSURL *url, NSString *error) {
    completed(url ? QUrl::fromLocalFile(QString::fromNSString(url.path)) : QUrl(),
      error ? QString::fromNSString(error) : QString());
  });
  });
}
