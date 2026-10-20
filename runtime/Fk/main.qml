// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtCore
import QtQuick.Dialogs
import QtQuick.Window
import Fk
import "../card-counter" as Counter

Window {
  id: root
  width: 1200
  height: 540
  minimumWidth: 200
  minimumHeight: 90
  color: "#13292e"
  readonly property bool androidMode: Cpp.os === "Android" || Cpp.os === "iOS"
  readonly property bool skinDebuggerMode: Qt.application.arguments.indexOf("--skin-debugger") !== -1
  visible: !skinDebuggerMode
  visibility: skinDebuggerMode ? Window.Hidden : (androidMode ? Window.FullScreen : Window.AutomaticVisibility)
  title: "新月杀测试版" + " v" + Cpp.version

  Counter.CounterHost { id: counterHost; navigationRoot: gamePage.item; photoLocations: StandardPaths.standardLocations(StandardPaths.PicturesLocation) }

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
    source: active ? Qt.resolvedUrl("../card-counter/../packages/freekill-core/Fk/Tools/SkinDebugger/Main.qml") : ""
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
