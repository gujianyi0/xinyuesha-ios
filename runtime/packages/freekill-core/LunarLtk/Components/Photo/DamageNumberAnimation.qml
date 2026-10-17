// Adapted from code by @EstKngAdone in lunarltk-qsgs-ui
import QtQuick
import Fk.Components.Common

GlowText {
  id: root
  property int num: 0
  property alias anim: anim

  anchors.horizontalCenter: parent.horizontalCenter
  y: (parent.height - height) / 2 + offset
  property real offset: -30

  text: `-${root.num}`
  font.pixelSize: 60
  font.family: "SimHei"
  font.bold: true
  color: '#c41e1e'
  glow.radius: 4
  glow.spread: 0.45
  glow.color: "black"
  opacity: 0
  z: 999

  SequentialAnimation {
    id: anim
    running: false
    PauseAnimation {
      duration: 100
    }

    ParallelAnimation {
      PropertyAnimation {
        target: root
        property: "opacity"
        from: 0.0
        to: 1.0
        duration: 70
      }

      PropertyAnimation {
        target: root
        property: "scale"
        from: 0.1
        to: 1.0
        duration: 70
      }

      SequentialAnimation {
        PropertyAnimation {
          target: root
          property: "offset"
          from: 20
          to: 10
          duration: 70
        }

        PauseAnimation {
          duration: 400
        }

        ParallelAnimation{
          PropertyAnimation {
            target: root
            property: "offset"
            from: 10
            to: -50
            duration: 300
          }
          PropertyAnimation {
            target: root
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: 300
          }
        }

        ScriptAction {
          script: root.destroy()
        }
      }
    }
  }
}
