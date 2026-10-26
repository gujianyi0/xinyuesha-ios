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
  UIWindow *game = UIApplication.sharedApplication.keyWindow;
  UIViewController *root = game.rootViewController;
  fkPickIosBackground(false, [this, game, root](QUrl url, QString error) {
    Q_ASSERT(busy);
    busy = false;
    Q_ASSERT_X(error.isEmpty(), "picker", qPrintable(error));
    // UIKit may retain its own keyboard/text-effects windows after PhotosUI.
    // Verify our actual game window, not the count of system-owned windows.
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
  engine.load(QUrl(QStringLiteral("qrc:/qt/qml/PickerHarness/Main.qml")));
  if (engine.rootObjects().isEmpty()) return 1;
  return app.exec();
}
