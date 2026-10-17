// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import Fk.Components.WaitingRoom

Popup {
  id: root
  objectName: "roomInvitationPrompt"
  anchors.centerIn: parent
  width: Math.min(440, parent.width - 24)
  height: Math.min(360, parent.height - 24)
  padding: 24
  modal: true
  closePolicy: Popup.NoAutoClose
  background: Rectangle {
    radius: 10; color: "#f2f6f3"
    border.color: "#8eb1ab"; border.width: 2
  }
  Connections {
    target: RoomInvites
    function onCurrentInvitationChanged() {
      if (RoomInvites.currentInvitation) root.open(); else root.close();
    }
  }
  Component.onCompleted: { if (RoomInvites.currentInvitation) open(); }
  contentItem: ColumnLayout {
    spacing: 14
    Text {
      text: Lua.tr("Room Invitation")
      font.pixelSize: 23; font.bold: true; color: "#42685f"
      Layout.alignment: Qt.AlignHCenter
    }
    Text {
      Layout.fillWidth: true
      text: Lua.tr("%1 invites you to a room").arg(RoomInvites.currentInvitation?.inviterName || "")
      textFormat: Text.PlainText
      font.pixelSize: 18; color: "#2f4941"
      wrapMode: Text.WrapAnywhere
    }
    Text {
      Layout.fillWidth: true
      text: Lua.tr("Room: %1").arg(RoomInvites.currentInvitation?.roomName || "")
      textFormat: Text.PlainText
      font.pixelSize: 17; color: "#2f4941"
      wrapMode: Text.WrapAnywhere
    }
    Text {
      Layout.fillWidth: true
      text: Lua.tr("Mode: %1").arg(Lua.tr(RoomInvites.currentInvitation?.mode || ""))
      textFormat: Text.PlainText
      font.pixelSize: 17; color: "#2f4941"
      wrapMode: Text.WrapAnywhere
    }
    Text {
      Layout.fillWidth: true
      text: Lua.tr("Join directly if a seat is available; otherwise spectate.")
      font.pixelSize: 14; color: "#617d75"
      wrapMode: Text.Wrap
    }
    Item { Layout.fillHeight: true }
    RowLayout {
      Layout.alignment: Qt.AlignRight
      spacing: 12
      WButton {
        objectName: "declineRoomInvitation"
        Layout.preferredWidth: 100; Layout.preferredHeight: 38
        text: Lua.tr("Decline")
        textFont.pixelSize: 18
        property string invitationToken: ""
        onPressedChanged: { if (pressed) invitationToken = RoomInvites.currentInvitation?.token || ""; }
        onClicked: RoomInvites.respond(false, invitationToken)
      }
      WButton {
        objectName: "acceptRoomInvitation"
        Layout.preferredWidth: 100; Layout.preferredHeight: 38
        text: Lua.tr("OK")
        textFont.pixelSize: 18
        title.color: "#f4faf6"; bg.color: "#8eb1ab"; border.width: 0
        property string invitationToken: ""
        onPressedChanged: { if (pressed) invitationToken = RoomInvites.currentInvitation?.token || ""; }
        onClicked: RoomInvites.respond(true, invitationToken)
      }
    }
  }
}
