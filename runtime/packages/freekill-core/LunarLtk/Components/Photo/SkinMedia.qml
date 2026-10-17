import QtQuick
import Qt5Compat.GraphicalEffects

Item {
  id: root
  property alias general: skin.general
  property alias skinName: skin.skinName
  property alias enabledShown: skin.enabledShown
  property alias hasDeputy: skin.hasDeputy
  function playAction(action) { return skin.playAction(action); }

  Rectangle {
    id: skinMask
    anchors.fill: parent
    color: 'black'
    visible: false
  }

  SkinArea {
    id: skin
    visible: false
    width: root.width * 2
    height: root.height * 2
  }

  OpacityMask {
    anchors.fill: parent
    source: skin
    maskSource: skinMask
  }
}
