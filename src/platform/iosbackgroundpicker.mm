// SPDX-License-Identifier: GPL-3.0-or-later
#include "iosbackgroundpicker.h"
#include <QGuiApplication>
#include <QInputMethod>
#include <QWindow>
#include <QPointer>
#import "iosbackgroundsession.h"
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>

bool fkReleaseClosedIosBackgroundPicker() {
  FKBackgroundPickerSession *session = fkActiveBackgroundSession;
  UIViewController *owned = session.presentation.ownedController;
  // A nil completion means the item-provider/confirmation already owns it.
  if (!session || !session->completion || !owned || owned.presentingViewController ||
      owned.isBeingPresented || owned.isBeingDismissed) return false;
  fkBackgroundTrace(@"recover-closed-session");
  // Finish silently before the replacement picker starts. An error dialog here
  // would itself compete for the same UIKit presentation controller.
  [session cancelPending]; return true;
}

void fkPickIosBackground(bool allowVideo, std::function<void(QUrl, QString)> completed) {
  // Resolve the originating Qt window BEFORE resetting the text responder.
  // keyWindow may temporarily be a UIKit keyboard/text-effects window.
  QWindow *origin = QGuiApplication::focusWindow();
  while (origin && origin->transientParent()) origin = origin->transientParent();
  const QPointer<QWindow> gameWindow(origin);
  // Finish Qt's current input delivery before handing focus to UIKit. In
  // particular, do not leave a QML text responder active beneath PhotosUI.
  if (QGuiApplication::inputMethod()) {
    QGuiApplication::inputMethod()->reset();
    QGuiApplication::inputMethod()->hide();
  }
  dispatch_async(dispatch_get_main_queue(), ^{
  UIView *gameView = gameWindow ? (__bridge UIView *)reinterpret_cast<void *>(gameWindow->winId()) : nil;
  UIWindow *window = gameView.window;
  fkBackgroundTrace(@"qt-origin", [NSString stringWithFormat:@"system=%@ window=%@ root=%@ attached=%d",
    UIDevice.currentDevice.systemVersion,
    window ? NSStringFromClass(window.class) : @"nil",
    window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"nil", gameView.window != nil]);
  if (!window || !window.rootViewController || window.rootViewController.isBeingDismissed) {
    completed({}, QStringLiteral("界面正在切换，请稍后再选图片")); return;
  }
  fkOpenBackgroundPicker(window, allowVideo, ^(NSURL *url, NSString *error) {
    completed(url ? QUrl::fromLocalFile(QString::fromNSString(url.path)) : QUrl(),
      error ? QString::fromNSString(error) : QString());
  });
  });
}
