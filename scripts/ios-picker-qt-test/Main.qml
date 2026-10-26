// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
Window {
  width: 900; height: 420; visible: true
  visibility: Window.FullScreen
  color: "#183137"
  Column {
    anchors.fill: parent; anchors.margins: 20; spacing: 12
    TextField {width:300;placeholderText:"Game chat";Accessible.name:"Game chat"}
    Item {
      width:parent.width; height:Math.min(240,parent.height-100)
      BGSetting {
        width:parent.width / scale
        scale: Math.min(1,parent.height / Math.max(1,implicitHeight))
        transformOrigin: Item.TopLeft
      }
    }
    Text {text:pickerBridge.status;color:"white";font.pixelSize:24;Accessible.role:Accessible.StaticText;Accessible.name:text}
  }
}
