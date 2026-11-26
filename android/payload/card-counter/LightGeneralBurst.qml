// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

Item {
  id: root
  objectName: "fkLightGeneralBurst"
  required property url artwork
  required property bool skill
  property real progress: 0

  anchors.centerIn: parent
  width: Math.min(parent.width * 1.12, 200)
  height: Math.min(parent.height * 0.68, 118)
  z: 8000

  Image {
    anchors.fill: parent
    source: root.artwork
    onStatusChanged: if (status === Image.Ready) console.log("[LightEffects] burst ready " + String(source).split("/").pop() + " skill=" + root.skill)
    fillMode: Image.PreserveAspectFit
    opacity: Math.min(root.progress * 8, (1 - root.progress) * 3, 1)
    scale: 0.68 + root.progress * (root.skill ? 0.59 : 0.42)
    rotation: root.skill ? -12 + root.progress * 26 : -17 + root.progress * 17
    transform: Translate { x: root.skill ? 0 : (root.progress - 0.5) * 24 }
  }

  NumberAnimation on progress {
    from: 0
    to: 1
    duration: root.skill ? 700 : 420
    easing.type: Easing.OutQuad
    onFinished: { console.log("[LightEffects] burst completed"); root.destroy(); }
  }
}
