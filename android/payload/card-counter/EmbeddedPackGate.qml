// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk

Rectangle {
  id: gate
  property bool checked: false
  property bool skipped: false
  property var preparation: ({})
  readonly property bool blocked: !checked || (!!preparation.required && preparation.state !== "ready" && !skipped)
  color: "#13292e"
  visible: blocked
  z: 10000
  function refresh() {
    try {
      const path = "effect-bundle/state.json";
      preparation = Backend.existsInAssets(path) ? JSON.parse(Backend.readFileFromAssets(path)) : ({});
      checked = true;
    } catch (_) { /* Wait for an atomic status file rather than loading config early. */ }
  }
  Component.onCompleted: refresh()
  Timer { interval: 400; running: gate.blocked; repeat: true; onTriggered: gate.refresh() }
  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - 48, 460)
    spacing: 16
    Label { text: gate.preparation.state === "error" ? "特效资源准备未完成" : "正在准备内置特效"; font.pixelSize: 24; color: "#eddfb6"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    Label { text: gate.preparation.title || "正在检查资源…"; color: "#d4e2df"; wrapMode: Text.Wrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    ProgressBar { from: 0; to: 3; value: gate.preparation.completed || 0; indeterminate: !gate.checked; Layout.fillWidth: true }
    Label { text: "首次启动需要一些时间。完成后自动进入，无需另行下载。"; color: "#afc4c1"; wrapMode: Text.Wrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    RowLayout {
      visible: gate.preparation.state === "error"
      Layout.alignment: Qt.AlignHCenter
      Button { text: "重试"; onClicked: { if (Backend.writeFileToAssets("effect-bundle/retry.json", "{}")) gate.preparation = {required: true, state: "preparing", title: "正在重试…", completed: 0}; } }
      Button { text: "退出"; onClicked: Qt.quit() }
    }
  }
}
