// SPDX-License-Identifier: GPL-3.0-or-later
#include "bridge.h"
#include "../../src/platform/iosbackgroundpicker.h"
#include "../../src/platform/iosuioverlay.h"
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QWindow>
#include <QTemporaryDir>
#include <QSettings>
#include <QQuickStyle>
#include <QTimer>
#import <UIKit/UIKit.h>

void PickerBridge::choose() { pickBackground(QStringLiteral("lobbyBg")); }
void PickerBridge::showDialog(const QString &, const QString &error) {
  Q_ASSERT_X(false, "background-settings", qPrintable(error));
}
void PickerBridge::save(const QString &lobby, const QString &room, const QString &portrait) {
  QSettings conf;
  conf.setValue("lobbyBg", lobby); conf.setValue("roomBg", room); conf.setValue("ladyImg", portrait);
  conf.sync(); Q_ASSERT(conf.status() == QSettings::NoError);
  for (const QString &key : {QString("lobbyBg"),QString("roomBg"),QString("ladyImg")}) {
    const QUrl url(conf.value(key).toString());
    if (url.isLocalFile()) Q_ASSERT(QFile::exists(url.toLocalFile()));
  }
}
void PickerBridge::pickBackground(const QString &key) {
  if (busy) fkReleaseClosedIosBackgroundPicker();
  Q_ASSERT(!busy); busy = true;
  m_status = QStringLiteral("Opening"); emit statusChanged();
  QWindow *origin = QGuiApplication::focusWindow();
  while (origin && origin->transientParent()) origin = origin->transientParent();
  Q_ASSERT(origin);
  UIView *view = (__bridge UIView *)reinterpret_cast<void *>(origin->winId());
  UIWindow *game = view.window;
  UIViewController *root = game.rootViewController;
  fkPickIosBackground(key == "roomBg", [this, key, game, root](QUrl url, QString error) {
    Q_ASSERT(busy); busy = false;
    const bool interrupted = QCoreApplication::arguments().contains("--interrupt-picker") && callbacks == 0;
    Q_ASSERT_X(error.isEmpty() || interrupted, "picker", qPrintable(error));
    Q_ASSERT(game.isKeyWindow && !game.hidden && game.rootViewController == root);
    if (!url.isEmpty()) Q_ASSERT(QFile::exists(url.toLocalFile()));
    emit backgroundPicked(key, url.toString(), error);
    // The real generated settings Connections saves synchronously.
    if (!url.isEmpty()) Q_ASSERT(QSettings().value(key).toString() == url.toString());
    m_status = (url.isEmpty() ? QStringLiteral("Cancelled ") : QStringLiteral("Selected ")) + QString::number(++callbacks);
    emit statusChanged();
  });
  if (callbacks == 0 && QCoreApplication::arguments().contains("--interrupt-picker")) {
    QTimer::singleShot(2000, this, [this, game] {
      // Model an external dismissal without calling our Cancel/result handler.
      [game.rootViewController.presentedViewController dismissViewControllerAnimated:NO completion:^{
        m_status = QStringLiteral("Interrupted"); emit statusChanged();
      }];
    });
  }
}
static void write(const QString &path, const QByteArray &data) {
  QDir().mkpath(QFileInfo(path).path());
  QFile f(path); Q_ASSERT(f.open(QIODevice::WriteOnly)); Q_ASSERT(f.write(data) == data.size());
}
int main(int argc, char **argv) {
  QApplication app(argc, argv);
  app.setOrganizationName("FreeKillTests"); app.setApplicationName("QtPickerHarness");
  QQuickStyle::setStyle("Material");
  PickerBridge bridge;
  QTemporaryDir generated;
  const QString dir = generated.path();
  QFile settings(":/stock/Fk/Pages/Lobby/BGSetting.qml"); Q_ASSERT(settings.open(QIODevice::ReadOnly));
  QString body = fkIosUiOverlay::adapt("Fk/Pages/Lobby/BGSetting.qml", QString::fromUtf8(settings.readAll()));
  qsizetype cursor = 0;
  for (const QString &name : {QString("Choose background"),QString("Choose room background"),QString("Choose music"),QString("Choose portrait")}) {
    cursor = body.indexOf("text: \"...\"", cursor); Q_ASSERT(cursor >= 0);
    const QString tagged = "text: \"...\"; Accessible.name: \"" + name + "\"";
    body.replace(cursor, QString("text: \"...\"").size(), tagged); cursor += tagged.size();
  }
  write(dir+"/BGSetting.qml", body.toUtf8());
  write(dir+"/Fk/qmldir", "module Fk\nsingleton Lua 1.0 Lua.qml\nsingleton Config 1.0 Config.qml\n");
  write(dir+"/Fk/Lua.qml", "pragma Singleton\nimport QtQuick\nQtObject {function tr(s){return s;}}\n");
  write(dir+"/Fk/Config.qml", "pragma Singleton\nimport QtQuick\nQtObject {property string lobbyBg:\"\";property string roomBg:\"\";property string ladyImg:\"\";property string bgmFile:\"\";property string language:\"zh_CN\";function saveConf(){pickerBridge.save(lobbyBg,roomBg,ladyImg);}}\n");
  QFile main(":/qt/qml/PickerHarness/Main.qml"); Q_ASSERT(main.open(QIODevice::ReadOnly));
  write(dir+"/Main.qml", main.readAll());
  QQmlApplicationEngine engine;
  engine.addImportPath(dir);
  engine.rootContext()->setContextProperty("pickerBridge", &bridge);
  engine.rootContext()->setContextProperty("Backend", &bridge);
  engine.load(QUrl::fromLocalFile(dir+"/Main.qml"));
  if (engine.rootObjects().isEmpty()) return 1;
  return app.exec();
}
