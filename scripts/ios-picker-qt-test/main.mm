// SPDX-License-Identifier: GPL-3.0-or-later
#include "bridge.h"
#include "../../src/platform/iosbackgroundpicker.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#import <UIKit/UIKit.h>

void PickerBridge::choose() {
  Q_ASSERT(!busy);
  busy = true;
  const NSUInteger windows = UIApplication.sharedApplication.windows.count;
  UIWindow *game = UIApplication.sharedApplication.keyWindow;
  UIViewController *root = game.rootViewController;
  fkPickIosBackground(false, [this, windows, game, root](QUrl url, QString error) {
    Q_ASSERT(busy);
    busy = false;
    Q_ASSERT_X(error.isEmpty(), "picker", qPrintable(error));
    Q_ASSERT(UIApplication.sharedApplication.windows.count == windows);
    Q_ASSERT(game.isKeyWindow && !game.hidden && game.rootViewController == root);
    if (!url.isEmpty()) {
      Q_ASSERT(QFile::exists(url.toLocalFile()));
      QFile::remove(url.toLocalFile());
    }
    m_status = (url.isEmpty() ? QStringLiteral("Cancelled ") : QStringLiteral("Selected ")) + QString::number(++callbacks);
    emit statusChanged();
  });
}
int main(int argc, char **argv) {
  QGuiApplication app(argc, argv);
  PickerBridge bridge;
  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("pickerBridge", &bridge);
  engine.loadFromModule("PickerHarness", "Main");
  if (engine.rootObjects().isEmpty()) return 1;
  return app.exec();
}
