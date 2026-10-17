// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import Fk.Components.WaitingRoom

Popup {
  id: root
  objectName: "roomInviteDialog"
  width: Math.min(420, parent.width - 24)
  height: Math.min(470, parent.height - 24)
  x: (parent.width - width) / 2
  y: (parent.height - height) / 2
  padding: 16
  modal: false
  closePolicy: Popup.CloseOnEscape
  background: Rectangle {
    radius: 10
    color: "#f2f6f3"
    border.color: "#8eb1ab"
    border.width: 2
  }
  onOpened: RoomInvites.subscribe(true)
  onClosed: RoomInvites.subscribe(false)
  Connections {
    target: RoomInvites
    function onCanInviteChanged() { if (!RoomInvites.canInvite) root.close(); }
  }

  contentItem: ColumnLayout {
    spacing: 12
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 36
      MouseArea {
        objectName: "roomInviteDragArea"
        anchors.fill: parent
        anchors.rightMargin: 46
        cursorShape: Qt.SizeAllCursor
        property point origin
        onPressed: mouse => { origin = mapToItem(root.parent, mouse.x, mouse.y); }
        onPositionChanged: mouse => {
          if (!pressed) return;
          const point = mapToItem(root.parent, mouse.x, mouse.y);
          root.x = Math.max(0, Math.min(root.parent.width - root.width, root.x + point.x - origin.x));
          root.y = Math.max(0, Math.min(root.parent.height - root.height, root.y + point.y - origin.y));
          origin = point;
        }
      }
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: Lua.tr("Invite Players")
        font.pixelSize: 22
        font.bold: true
        color: "#42685f"
      }
      WButton {
        objectName: "roomInviteCloseButton"
        anchors.right: parent.right
        width: 36; height: 32
        text: "×"
        textFont.pixelSize: 24
        onClicked: root.close()
      }
    }
    Text {
      Layout.fillWidth: true
      text: Lua.tr("Online players in the lobby · updates automatically")
      font.pixelSize: 14
      color: "#617d75"
      wrapMode: Text.Wrap
    }
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#cadbd4" }
    ListView {
      id: list
      objectName: "roomInvitePlayerList"
      Layout.fillWidth: true
      Layout.fillHeight: true
      model: RoomInvites.players
      clip: true
      spacing: 8
      ScrollBar.vertical: ScrollBar {}
      delegate: Rectangle {
        id: row
        required property var modelData
        width: list.width - 12
        height: 52
        radius: 6
        color: "#e3ece6"
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.right: inviteButton.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.name
          textFormat: Text.PlainText
          font.pixelSize: 18
          color: "#2f4941"
          elide: Text.ElideRight
        }
        WButton {
          id: inviteButton
          objectName: "invitePlayer_" + row.modelData.id
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 118; height: 34
          property int remaining: RoomInvites.remaining(row.modelData.id)
          property bool pending: !!RoomInvites.pendingPlayers[String(row.modelData.id)]
          enabled: !pending && remaining === 0
          text: pending ? Lua.tr("Inviting...") : remaining ? Lua.tr("Invited (%1s)").arg(remaining) : Lua.tr("Invite")
          textFont.pixelSize: 16
          title.color: "#f4faf6"
          bg.color: "#8eb1ab"
          bg.radius: 6
          border.width: 0
          onClicked: RoomInvites.invite(row.modelData.id)
        }
      }
      Text {
        anchors.centerIn: parent
        width: parent.width - 24
        visible: list.count === 0
        text: RoomInvites.listError || Lua.tr("No players available to invite")
        textFormat: Text.PlainText
        color: "#617d75"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }
    }
    Text {
      Layout.fillWidth: true
      text: Lua.tr("Drag the header to move · invite again after 5 seconds")
      color: "#617d75"
      font.pixelSize: 13
      wrapMode: Text.Wrap
    }
  }
}
