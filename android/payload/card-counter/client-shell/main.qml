// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Dialogs
import QtQuick.Window
import Fk
import ".." as Counter

Window {
  id: root
  width: 1200
  height: 540
  minimumWidth: 200
  minimumHeight: 90
  color: "#13292e"
  readonly property bool androidMode: Cpp.os === "Android"
  readonly property bool skinDebuggerMode: Qt.application.arguments.indexOf("--skin-debugger") !== -1
  visible: !skinDebuggerMode
  visibility: skinDebuggerMode ? Window.Hidden : (androidMode ? Window.FullScreen : Window.AutomaticVisibility)
  title: "新月杀测试版" + " v" + Cpp.version

  Counter.CounterHost { id: counterHost }

  onXChanged: if (!skinDebuggerMode && !androidMode) Config.winX = x;
  onYChanged: if (!skinDebuggerMode && !androidMode) Config.winY = y;
  onWidthChanged: if (!skinDebuggerMode) Config.winWidth = width;
  onHeightChanged: if (!skinDebuggerMode) Config.winHeight = height;
  onActiveChanged: if (active && androidMode && !skinDebuggerMode) Qt.callLater(root.showFullScreen)

  Counter.CounterViewport {
    id: viewport
    onContentScaleChanged: if (!root.skinDebuggerMode) Config.winScale = contentScale;
    Loader {
      id: gamePage
      anchors.fill: parent
      active: !root.skinDebuggerMode
      sourceComponent: Component {
        RootPage {
          id: mainWindow
          anchors.fill: parent
          Counter.SocialHost { id: socialHost }
          property bool sourcesPrepared: false
          property var pendingPackages: null
          property string sourceRequest: ""
          property double sourceDeadline: 0
          onSheduledDownloadChanged: {
            if (!sheduledDownload || sourcesPrepared) return;
            const packages = sheduledDownload;
            sheduledDownload = null; // prevent the stock updater starting early
            const requested = [];
            let valid = typeof packages.length === "number" && packages.length <= 512;
            for (const item of valid ? packages : []) {
              const name = String(item.name || ""), url = String(item.url || "");
              if (!/^[A-Za-z0-9_-]{1,128}$/.test(name) || !/^https?:\/\/[^\s"\\]+$/.test(url)) { valid = false; break; }
              requested.push({name:name,url:url});
            }
            sourceRequest = Date.now().toString() + "_" + Math.floor(Math.random()*1000000000);
            sourceDeadline = Date.now() + 20000;
            if (!valid || !Backend.writeFileToAssets("package-sync/request.json",JSON.stringify({id:sourceRequest,packages:requested}))) {
              sourceRequest = ""; mainWindow.busy = false;
              Backend.showDialog("Error","无法保存扩展包下载源，已保留本地资源，请重启后重试。");
              return;
            }
            pendingPackages = packages;
          }
          Timer {
            interval: 200; repeat: true; running: mainWindow.pendingPackages !== null
            onTriggered: {
              let reply = null;
              try { reply = JSON.parse(Backend.readFileFromAssets("package-sync/reply.json") || "null"); } catch (_) {}
              if (reply && reply.id === mainWindow.sourceRequest) {
                if (reply.ok === true) {
                  // UpdatePackage is followed by a server disconnect. Wait until
                  // BackToStart and Client destruction finish before downloading.
                  if (typeof ClientInstance !== "undefined" && ClientInstance) return;
                  const packages = mainWindow.pendingPackages;
                  mainWindow.pendingPackages = null;
                  mainWindow.sourcesPrepared = true;
                  mainWindow.sheduledDownload = packages;
                  mainWindow.tryUpdatePackage();
                  mainWindow.sourcesPrepared = false;
                } else {
                  mainWindow.pendingPackages = null; mainWindow.busy = false;
                  Backend.showDialog("Error",reply.error || "扩展包下载源同步失败，请重启后重试。");
                }
              } else if (Date.now() > mainWindow.sourceDeadline) {
                mainWindow.pendingPackages = null; mainWindow.busy = false;
                Backend.showDialog("Error","下载源同步超时，资源已保留，请重启后重试。");
              }
            }
          }
          onConfLoaded: {
            counterHost.settingsReady = true;
            if (!root.androidMode) {
              root.x = Config.winX; root.y = Config.winY;
              root.width = Config.winWidth; root.height = Config.winHeight;
            } else {
              // loadConf may have restored desktop/previous orientation sizes.
              // Popup geometry must use the current native surface.
              Config.winWidth = root.width; Config.winHeight = root.height;
              // Android owns the surface geometry. Screen metrics can be stale
              // during startup, rotation, cutout/inset changes and density changes.
              Qt.callLater(root.showFullScreen);
            }
            Config.winScale = viewport.contentScale;
          }
        }
      }
    }
  }

  Loader {
    active: root.skinDebuggerMode
    source: active ? Qt.resolvedUrl("../../packages/freekill-core/Fk/Tools/SkinDebugger/Main.qml") : ""
  }
  MessageDialog {
    id: exitMessageDialog
    title: root.title
    informativeText: qsTr("Are you sure to exit?")
    buttons: MessageDialog.Ok | MessageDialog.Cancel
    onButtonClicked: function(button, role) {
      if (button === MessageDialog.Ok) {
        if (gamePage.item) gamePage.item.closing = true;
        Config.saveConf(); Cpp.quitLobby(false); root.close();
      } else exitMessageDialog.close();
    }
  }
  Shortcut {
    sequences: ["F11", "Ctrl+F", "Alt+Return"]
    onActivated: {
      if (root.androidMode || root.visibility !== Window.FullScreen) root.showFullScreen();
      else root.showNormal();
    }
  }
  onClosing: function(closeEvent) {
    if (root.skinDebuggerMode) Qt.quit();
    else if (gamePage.item && !gamePage.item.closing) {
      closeEvent.accepted = false; exitMessageDialog.open();
    }
  }
}
