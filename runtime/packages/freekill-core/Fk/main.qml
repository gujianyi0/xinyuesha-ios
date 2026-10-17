import QtQuick
import QtQuick.Dialogs
import QtQuick.Window
import Fk

Window {
  id: root
  width: 1200
  height: 540
  minimumWidth: 200
  minimumHeight: 90
  readonly property bool skinDebuggerMode: Qt.application.arguments.indexOf("--skin-debugger") !== -1
  visible: !skinDebuggerMode

  title: qsTr("FreeKill") + " v" + Cpp.version

  onXChanged: if (!skinDebuggerMode) Config.winX = x;
  onYChanged: if (!skinDebuggerMode) Config.winY = y;
  onWidthChanged: if (!skinDebuggerMode) Config.winWidth = width;
  onHeightChanged: if (!skinDebuggerMode) Config.winHeight = height;

  Loader {
    id: gamePage
    active: !root.skinDebuggerMode
    anchors.centerIn: parent
    sourceComponent: Component {
      RootPage {
        id: mainWindow

        width: (root.width / root.height < 1200 / 540) ? 1200 : 540 * root.width / root.height
        height: (root.width / root.height > 1200 / 540) ? 540 : 1200 * root.height / root.width
        scale: root.width / width
        anchors.centerIn: parent

        onScaleChanged: Config.winScale = scale;
        onConfLoaded: {
          if (Cpp.os != "Android") {
            root.x = Config.winX;
            root.y = Config.winY;
            root.width = Config.winWidth;
            root.height = Config.winHeight;
          } else {
            // 安卓强制拉满整个Screen！
            root.width = Screen.width;
            root.height = Screen.height;
            Config.winWidth = root.width;
            Config.winHeight = root.height;
          }
        }
      }
    }
  }

  Loader {
    active: root.skinDebuggerMode
    source: active ? Qt.resolvedUrl("Tools/SkinDebugger/Main.qml") : ""
  }

  MessageDialog {
    id: exitMessageDialog
    title: root.title
    informativeText: qsTr("Are you sure to exit?")
    buttons: MessageDialog.Ok | MessageDialog.Cancel
    onButtonClicked: function (button, role) {
      switch (button) {
        case MessageDialog.Ok: {
          gamePage.item.closing = true;
          Config.saveConf();
          Cpp.quitLobby(false);
          root.close();
          break;
        }
        case MessageDialog.Cancel: {
          exitMessageDialog.close();
        }
      }
    }
  }

  Shortcut {
    sequences: [ "F11", "Ctrl+F", "Alt+Return" ]
    onActivated: {
      if (root.visibility === Window.FullScreen)
        root.showNormal();
      else
        root.showFullScreen();
    }
  }

  onClosing: (closeEvent) => {
    if (root.skinDebuggerMode) {
      Qt.quit();
    } else if (gamePage.item && !gamePage.item.closing) {
      closeEvent.accepted = false;
      exitMessageDialog.open();
    }
  }
}
