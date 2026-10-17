// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Fk

ColumnLayout {
  id: userInfo
  readonly property real actionWidth: Math.max(avatarUpdate.implicitWidth, titleUpdate.implicitWidth, passwordUpdate.implicitWidth)
  Component.onCompleted: {
    if (Config.titleServerSupported || Config.consoleStartRequested) Config.requestTitleProfile();
  }
  // anchors.centerIn: parent

  RowLayout {
    Layout.fillWidth: true
    spacing: 16
    Text {
      Layout.preferredWidth: 100
      text: Lua.tr("Username")
    }
    Text {
      text: Self.screenName
      visible: !Config.hideScreenName
      font.pixelSize: 18
    }
  }

  Timer {
    id: opTimer
    interval: 1000
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 16
    Text {
      Layout.preferredWidth: 100
      text: Lua.tr("Avatar")
    }
    TextField {
      id: avatarName
      maximumLength: 64
      font.pixelSize: 18
      text: Self.avatar
      Layout.fillWidth: true
    }
    Button {
      id: avatarUpdate
      Layout.preferredWidth: userInfo.actionWidth
      text: Lua.tr("Update Avatar")
      enabled: avatarName.text !== "" && !opTimer.running
      onClicked: {
        App.setBusy(true);
        opTimer.start();
        ClientInstance.notifyServer(
          "UpdateAvatar",
          avatarName.text
        );
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 16
    Text { Layout.preferredWidth: 100; text: Lua.tr("Title") }
    TextField {
      Layout.fillWidth: true
      readOnly: true
      font.pixelSize: 18
      text: Config.myTitle ? "【" + Config.myTitle + "】" : Lua.tr("(None)")
    }
    Button {
      id: titleUpdate
      Layout.preferredWidth: userInfo.actionWidth
      text: Config.titlePending ? "更新中…" : "更换称号"
      enabled: Config.titleServerSupported && !Config.titlePending
      onClicked: titleMenu.open()
      Menu {
        id: titleMenu
        MenuItem { text: Lua.tr("(None)"); onTriggered: Config.equipTitle("") }
        Repeater {
          model: Config.ownedTitles
          MenuItem {
            required property var modelData
            text: "【" + modelData.title + "】"
            onTriggered: Config.equipTitle(modelData.id)
          }
        }
      }
    }
  }
  Text {
    Layout.leftMargin: 116
    text: Config.titleServerSupported ? (Config.ownedTitles.length ? "" : "暂无称号") : "服务器未启用称号"
    visible: text !== ""
  }

  Button {
    Layout.leftMargin: 116
    text: "称号样式预览"
    visible: Config.titleTestEdition
    onClicked: {
      if (titlePreview.item) (titlePreview.item as Popup).open();
      else titlePreview.active = true;
    }
  }
  Loader {
    id: titlePreview
    active: false
    source: Config.titleTestEdition ? Cpp.path + "/packages/player_titles_test/qml/TitlePreview.qml" : ""
    onLoaded: (item as Popup).open()
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 16
    Text {
      Layout.preferredWidth: 100
      text: Lua.tr("Old Password")
    }
    TextField {
      id: oldPassword
      echoMode: TextInput.Password
      passwordCharacter: "*"
      Layout.rightMargin: userInfo.actionWidth + 16
      font.pixelSize: 18
      Layout.fillWidth: true
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 16
    Text {
      Layout.preferredWidth: 100
      text: Lua.tr("New Password")
    }
    TextField {
      id: newPassword
      font.pixelSize: 18
      echoMode: TextInput.Password
      passwordCharacter: "*"
      Layout.fillWidth: true
    }
    Button {
      id: passwordUpdate
      Layout.preferredWidth: userInfo.actionWidth
      text: Lua.tr("Update Password")
      enabled: oldPassword.text !== "" && newPassword.text !== ""
               && !opTimer.running
      onClicked: {
        App.setBusy(true);
        opTimer.start();
        ClientInstance.notifyServer(
          "UpdatePassword",
          [oldPassword.text, newPassword.text]
        );
      }
    }
  }
}
