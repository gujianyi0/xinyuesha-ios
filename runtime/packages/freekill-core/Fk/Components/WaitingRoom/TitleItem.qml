import QtQuick
import Fk

Item {
  id: root
  implicitWidth: TitleBank.badgeWidth
  implicitHeight: TitleBank.badgeHeight
  width: implicitWidth
  height: TitleBank.heightForWidth(width)
  clip: true
  property string title: ""
  property string style: "indigo"
  readonly property var appearance: TitleBank.resolve(style)
  readonly property var customItem: customTitle.item
  property bool customReady: false
  Rectangle {
    objectName: "titleBackplate"
    anchors.fill: parent
    radius: Math.min(4, height / 4)
    color: root.appearance.background || "#838383"
    border.color: root.appearance.border || "#cecccd"
    border.width: 1
    // Transparent/illustrated badges bring their own plate. Other styles keep this shared background.
    visible: !root.customReady || root.appearance.backgroundMode !== "component"
    Rectangle {
      anchors.fill: parent
      anchors.margins: 2
      radius: Math.max(0, parent.radius - 1)
      color: "transparent"
      border.width: .5
      border.color: "#55ffffff"
    }
  }
  Loader {
    id: customTitle
    anchors.fill: parent
    source: TitleBank.componentSource(root.style)
    visible: root.customReady
    onLoaded: root.customReady = item !== null && ("title" in item)
    onStatusChanged: if (status !== Loader.Ready) root.customReady = false
  }
  Binding {
    target: root.customItem
    property: "title"
    value: root.title
    when: root.customReady
  }
  Text {
    id: titleText
    height: parent.height
    width: parent.width - 12
    elide: Text.ElideRight
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.title
    font.bold: true
    font.pixelSize: Math.max(1, 14 * root.height / TitleBank.badgeHeight)
    font.family: root.appearance.fontFamily || "Arial"
    textFormat: Text.PlainText
    visible: !root.customReady
    color: root.appearance.color || "snow"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
