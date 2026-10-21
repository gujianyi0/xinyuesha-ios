// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import LunarLtk

Item {
  id: root
  objectName: "roleVoiceControl"
  required property var chatBox
  required property var soundList
  property string selectedGeneral: ""
  property var generals: []
  property var filtered: []
  property string notice: ""
  property bool installed: false
  property bool revealSelected: false
  readonly property bool pickerVisible: picker.visible
  implicitWidth: 56
  implicitHeight: 44
  Layout.preferredWidth: 56
  Layout.preferredHeight: 44
  visible: !chatBox.isLobby && !Config.replaying

  function refreshPool() {
    try {
      const data = Lua.ev('(function() local ret = {} if not (Fk and ClientInstance) then return ret end ' +
        'for _, g in ipairs(Fk:getAllGenerals()) do ' +
        'if not g.hidden and not g.total_hidden then table.insert(ret, {id=g.name, name=Fk:translate(g.name), pack=Fk:translate(g.package.name)}) end end ' +
        'table.sort(ret, function(a,b) return a.id < b.id end) return ret end)()');
      generals = JSON.parse(JSON.stringify(data || []));
      if (!Array.isArray(generals)) generals = [];
      if (selectedGeneral && !generals.some(g => g.id === selectedGeneral)) selectedGeneral = "";
      filterPool();
      notice = generals.length ? "" : "当前房间暂无可选武将，请进入房间后重试";
    } catch (_) { generals = []; filtered = []; notice = "暂时无法读取房主将池，请稍后重试"; }
  }
  function filterPool() {
    const text = search.text.trim().toLowerCase();
    filtered = generals.filter(g => !text || (g.id + " " + g.name + " " + g.pack).toLowerCase().indexOf(text) >= 0);
  }
  function allowed(general) {
    try { return Lua.ev('Fk:canUseGeneral(' + JSON.stringify(general) + ')') === true; }
    catch (_) { return false; }
  }
  function rebuildVoices() {
    if (!soundList.visible) return;
    chatBox.loadSkills();
    if (!selectedGeneral) return;
    if (!allowed(selectedGeneral)) { selectedGeneral = ""; notice = "房主已禁用该武将，请重新选择"; return; }
    const self = Lua.selfPlayer;
    if (selectedGeneral === self.general || selectedGeneral === self.deputyGeneral) return;
    const before = soundList.model.count;
    chatBox.loadGeneralSkillAudios(selectedGeneral);
    const info = Ltk.getGeneralData(selectedGeneral);
    for (const type of ["win", "death"]) {
      const path = SkinBank.getAudioRealPath(selectedGeneral, info.extension, type);
      if (path && Backend.exists(path)) soundList.model.append({name:(type === "win" ? "!" : "~") + selectedGeneral, idx:0, specific:false, general:selectedGeneral});
    }
    notice = soundList.model.count === before ? "这个武将暂无已下载的语音" : "";
    const added = soundList.model.count - before;
    if (added > 0) soundList.model.move(before, 0, added);
    if (revealSelected) {
      revealSelected = false;
      Qt.callLater(function() { root.soundList.positionViewAtBeginning(); });
    }
  }
  function choose(general) {
    if (general && !allowed(general)) { notice = "该武将不在房主当前将池中"; return; }
    selectedGeneral = general; revealSelected = true; picker.close();
    if (soundList.visible) rebuildVoices();
    else soundList.visible = true;
  }
  function voiceText(row) {
    const name = String(row.name || ""), idx = Number(row.idx || 0);
    const special = name.startsWith("!") || name.startsWith("~");
    const key = special ? name : "$" + name + (row.specific ? "_" + row.general : "") + (idx ? idx : "");
    const translated = Lua.tr(key);
    const label = translated === key ? (special ? Lua.tr(name.slice(1)) + (name[0] === "!" ? " · 胜利" : " · 阵亡") : Lua.tr(name) + (idx ? " · " + idx : "")) : translated;
    return row.general && row.general === selectedGeneral ? "【" + Lua.tr(row.general) + "】" + label : label;
  }
  function sendVoice(row) {
    if (cooldown.running || Config.replaying || chatBox.isLobby) return false;
    let name = String(row.name || ""), general = String(row.general || "");
    const special = name.startsWith("!") || name.startsWith("~");
    if (special) general = name.slice(1);
    const self = Lua.selfPlayer;
    if (general && general !== self.general && general !== self.deputyGeneral && !allowed(general)) {
      notice = "房主已禁用该武将，请重新选择"; return false;
    }
    if (!name || /[\r\n:]/.test(name + general)) return false;
    if (name === "fastchat_m" && self.general && Ltk.getGeneralDetail(self.general).gender !== 1) name = "fastchat_f";
    const idx = Number(row.idx || 0);
    if (!Number.isInteger(idx) || idx < 0 || idx >= 999) return false;
    const msg = special ? "$" + name : "$" + name + ":" + (idx ? idx : "") + (row.specific && general ? ":" + general : "");
    ClientInstance.notifyServer("Chat", {type:2, msg:msg});
    cooldown.start(); soundList.visible = false; return true;
  }
  Timer { id: cooldown; interval:1500 }
  Connections {
    target: root.soundList
    function onVisibleChanged() { if (root.soundList.visible) Qt.callLater(root.rebuildVoices); }
  }
  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) {
      if (["EnterRoom","ChangeRoom","EnterLobby","BackToStart"].indexOf(command) >= 0) {
        root.selectedGeneral = ""; root.generals = []; root.filtered = []; picker.close();
      }
    }
  }
  property Component voiceDelegate: Component {
    ItemDelegate {
      required property var model
      width: root.soundList.width
      implicitHeight: Math.max(40,contentItem.implicitHeight + 12)
      text: root.voiceText(model)
      enabled: !cooldown.running
      onClicked: root.sendVoice(model)
    }
  }
  Button {
    anchors.fill: parent
    objectName: "roleVoiceButton"
    text: "角色"
    leftPadding: 4; rightPadding: 4
    font.pixelSize: 14
    Accessible.name: "选择角色语音"
    ToolTip.visible: hovered
    ToolTip.text: root.selectedGeneral ? "语音角色：" + Lua.tr(root.selectedGeneral) : "选择房主将池中的角色语音"
    onClicked: { root.refreshPool(); picker.open(); }
  }
  Popup {
    id: picker
    objectName: "roleVoicePicker"
    palette.window: "#f5f3ec"
    palette.windowText: "#202c2e"
    palette.text: "#202c2e"
    background: Rectangle { color: "#f5f3ec"; radius: 8; border.color: "#ac9661"; border.width: 1 }
    parent: root.chatBox
    x: 4; y: 4
    width: Math.max(100,parent.width - 8)
    height: Math.max(100,parent.height - 8)
    padding: 10
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    ColumnLayout {
      anchors.fill: parent
      RowLayout {
        Label { text:"角色语音";font.bold:true;Layout.fillWidth:true }
        Button { text:"当前武将";onClicked:root.choose("") }
        Button { text:"关闭";onClicked:picker.close() }
      }
      TextField { id:search;Layout.fillWidth:true;placeholderText:"搜索角色或扩展包";onTextChanged:filterDelay.restart() }
      Label { Layout.fillWidth:true;wrapMode:Text.Wrap;text:root.notice || "仅显示房主当前启用的将池；选择后在语音列表发送" }
      ListView {
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true
        model:root.filtered
        ScrollBar.vertical:ScrollBar {}
        delegate:ItemDelegate {
          required property var modelData
          width:ListView.view.width;height:52
          text:modelData.name + " · " + modelData.pack
          highlighted:root.selectedGeneral === modelData.id
          onClicked:root.choose(modelData.id)
        }
      }
    }
  }
  Timer { id:filterDelay;interval:150;onTriggered:root.filterPool() }
  Component.onCompleted: { soundList.delegate = voiceDelegate; installed = true; }
}
