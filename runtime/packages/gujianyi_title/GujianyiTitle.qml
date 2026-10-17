// SPDX-License-Identifier: GPL-3.0-or-later
// 专属称号：故剑遗。黑金 + 深海神秘（克苏鲁）风格。
import QtQuick
import Qt5Compat.GraphicalEffects

Item {
  id: root
  property string title: ""
  implicitWidth: 110
  implicitHeight: 30
  clip: true

  readonly property real u: height / 30

  Rectangle {
    anchors.fill: parent
    radius: Math.min(4, 4 * root.u)
    border.width: Math.max(1, 1 * root.u)
    border.color: "#b8913d"
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#111b1a" }
      GradientStop { position: 0.45; color: "#050809" }
      GradientStop { position: 1.0; color: "#0d1716" }
    }
  }

  // 内侧金线
  Rectangle {
    anchors.fill: parent
    anchors.margins: Math.max(1, 2 * root.u)
    radius: Math.min(3, 3 * root.u)
    color: "transparent"
    border.width: Math.max(0.6, 0.7 * root.u)
    border.color: "#5d4a22"
  }

  Canvas {
    id: art
    anchors.fill: parent
    opacity: 0.9
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      const ctx = getContext("2d");
      const w = width, h = height, u = root.u;
      ctx.clearRect(0, 0, w, h);
      ctx.lineCap = "round";

      // 两侧触手：从边缘卷向中央，深海旧日支配者的轮廓
      ctx.strokeStyle = "rgba(190, 155, 72, 0.42)";
      ctx.lineWidth = Math.max(0.7, 0.9 * u);
      for (let i = 0; i < 3; i++) {
        const y = h * (0.3 + i * 0.22);
        ctx.beginPath();
        ctx.moveTo(-2, y);
        ctx.bezierCurveTo(w * 0.10, y - h * (0.10 + i * 0.02),
                          w * 0.20, y + h * (0.12 + i * 0.02),
                          w * 0.27, y - h * 0.02);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(w + 2, y);
        ctx.bezierCurveTo(w * 0.90, y - h * (0.10 + i * 0.02),
                          w * 0.80, y + h * (0.12 + i * 0.02),
                          w * 0.73, y - h * 0.02);
        ctx.stroke();
      }

      // 左右各一只“古神之眼”
      const drawEye = (x) => {
        ctx.fillStyle = "rgba(206, 172, 88, 0.75)";
        ctx.beginPath();
        ctx.ellipse(x, h * 0.5, h * 0.115, h * 0.06, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = "#050708";
        ctx.beginPath();
        ctx.ellipse(x, h * 0.5, h * 0.028, h * 0.055, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = "rgba(224, 195, 120, 0.9)";
        ctx.beginPath();
        ctx.arc(x, h * 0.5, Math.max(0.5, h * 0.012), 0, Math.PI * 2);
        ctx.fill();
      };
      drawEye(w * 0.075);
      drawEye(w * 0.925);

      // 星尘
      ctx.fillStyle = "rgba(198, 164, 84, 0.5)";
      const specks = [[0.18, 0.24], [0.22, 0.78], [0.78, 0.22], [0.82, 0.76], [0.5, 0.12], [0.5, 0.88]];
      for (const s of specks) {
        ctx.beginPath();
        ctx.arc(w * s[0], h * s[1], Math.max(0.4, 0.7 * u), 0, Math.PI * 2);
        ctx.fill();
      }

      // 上下金线
      ctx.strokeStyle = "rgba(200, 166, 82, 0.55)";
      ctx.lineWidth = Math.max(0.5, 0.6 * u);
      ctx.beginPath();
      ctx.moveTo(w * 0.16, h * 0.16);
      ctx.lineTo(w * 0.36, h * 0.16);
      ctx.moveTo(w * 0.64, h * 0.16);
      ctx.lineTo(w * 0.84, h * 0.16);
      ctx.moveTo(w * 0.16, h * 0.84);
      ctx.lineTo(w * 0.36, h * 0.84);
      ctx.moveTo(w * 0.64, h * 0.84);
      ctx.lineTo(w * 0.84, h * 0.84);
      ctx.stroke();
    }
  }

  Text {
    id: label
    anchors.centerIn: parent
    width: parent.width - Math.max(18, 30 * root.u)
    text: root.title
    color: "#f3dc95"
    font.family: Qt.platform.os === "ios" ? "PingFang SC" : "Microsoft YaHei"
    font.bold: true
    font.pixelSize: Math.max(9, 14 * root.u)
    font.letterSpacing: 0.4 * root.u
    style: Text.Outline
    styleColor: "#2b1f0b"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    visible: false
  }
  Glow {
    anchors.fill: label
    source: label
    color: "#c9a24a"
    spread: 0.25
    radius: 4 * root.u
    samples: 12
  }
  LinearGradient {
    anchors.fill: label
    source: label
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#fff1bd" }
      GradientStop { position: 0.55; color: "#e8c977" }
      GradientStop { position: 1.0; color: "#a97f2d" }
    }
  }

  // 缓慢的幽光呼吸
  Rectangle {
    anchors.fill: parent
    radius: Math.min(4, 4 * root.u)
    color: "transparent"
    border.width: Math.max(0.8, 1.1 * root.u)
    border.color: "#7ce0c8"
    opacity: 0.0
    SequentialAnimation on opacity {
      loops: Animation.Infinite
      NumberAnimation { to: 0.14; duration: 2600; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.02; duration: 3200; easing.type: Easing.InOutSine }
    }
  }
}
