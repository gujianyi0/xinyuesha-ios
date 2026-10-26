// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
Window {
  width: 900; height: 420; visible: true
  visibility: Window.FullScreen
  color: "#183137"
  Column {
    x: 40; y: 30; spacing: 16
    TextField {width:300;placeholderText:"Game chat";Accessible.name:"Game chat"}
    Button {text:"Choose background";onClicked:pickerBridge.choose()}
    Text {text:pickerBridge.status;color:"white";font.pixelSize:24;Accessible.role:Accessible.StaticText;Accessible.name:text}
  }
}
