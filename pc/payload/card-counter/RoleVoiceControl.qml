// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
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
  property var candidates: []
  property int checkedCount: 0
  property bool scanning: false
  property var audioCache: ({})
  property var directoryCache: ({})
  property var metadataCache: ({})
  property var availabilityCache: ({})
  property var voiceCache: ({})
  property string resourceKey: ""
  readonly property bool pickerVisible: picker.visible
  implicitWidth: 56
  implicitHeight: 44
  Layout.preferredWidth: 56
  Layout.preferredHeight: 44
  visible: !chatBox.isLobby && !Config.replaying

  function clearAudioCache() {
    audioCache = {}; directoryCache = {}; metadataCache = {};
    availabilityCache = {}; voiceCache = {};
  }
  // Index each audio directory once. File probes and metadata are shared by
  // generals with the same skills; the animated table is never scanned.
  function audioPath(name, extension, kind) {
    const key = JSON.stringify([extension, kind, name]);
    if (key in audioCache) return audioCache[key];
    if (typeof Backend.ls === "function" && typeof Cpp.path === "string" && Cpp.path) {
      const dirKey = JSON.stringify([extension, kind]);
      if (!(dirKey in directoryCache)) {
        const names = new Set();
        const packs = Array.from(Config.enabledResourcePacks || []);
        const bases = packs.map(p => Cpp.path + "/resource_pak/" + p + "/packages/");
        bases.push(Cpp.path + "/packages/");
        for (const base of bases) {
          for (const file of Backend.ls(base + extension + "/audio/" + kind + "/")) names.add(file);
        }
        directoryCache[dirKey] = names;
      }
      if (!directoryCache[dirKey].has(name + ".mp3")) { audioCache[key] = ""; return ""; }
    }
    const path = SkinBank.getAudioRealPath(name, extension, kind);
    audioCache[key] = path && Backend.exists(path) ? path : "";
    return audioCache[key];
  }
  function metadata(general) {
    if (!(general in metadataCache)) metadataCache[general] = {
      info: Ltk.getGeneralData(general), detail: Ltk.getGeneralDetail(general)
    };
    return metadataCache[general];
  }
  function collectVoices(general, firstOnly) {
    const meta = metadata(general), rows = [], extension = meta.info.extension;
    for (const skill of (meta.detail.skill || [])) {
      if (!skill.name || skill.name.startsWith("#")) continue;
      // Match the stock protocol: specific voice first, otherwise shared skill
      // audio; index 0 is optional, index 1 starts the numbered sequence.
      const specificName = skill.name + "_" + general;
      let specific = !!(audioPath(specificName, extension, "skill") || audioPath(specificName + "1", extension, "skill"));
      const data = specific ? meta.info : Ltk.getSkillData(skill.name);
      if (!data) continue;
      const stem = specific ? specificName : skill.name;
      for (let i = 0; i < 999; i++) {
        const path = audioPath(stem + (i ? i : ""), data.extension, "skill");
        if (path) {
          rows.push({name:skill.name, idx:i, specific:specific, general:general});
          if (firstOnly) return rows;
        } else if (i > 0) break;
      }
    }
    for (const kind of ["win", "death"]) {
      if (audioPath(general, extension, kind)) {
        rows.push({name:(kind === "win" ? "!" : "~") + general, idx:0, specific:false, general:general});
        if (firstOnly) return rows;
      }
    }
    return rows;
  }
  function hasVoices(general) {
    if (!(general in availabilityCache)) {
      try { availabilityCache[general] = collectVoices(general, true).length > 0; }
      catch (_) { availabilityCache[general] = false; }
    }
    return availabilityCache[general];
  }
  function voices(general) {
    if (!(general in voiceCache)) voiceCache[general] = collectVoices(general, false);
    return voiceCache[general];
  }
  function refreshPool(force) {
    scanDelay.stop(); scanning = false;
    try {
      const key = JSON.stringify(Config.enabledResourcePacks || []);
      if (force || key !== resourceKey) { clearAudioCache(); resourceKey = key; }
      const data = Lua.ev('(function() local ret = {} if not (Fk and ClientInstance) then return ret end ' +
        'for _, g in ipairs(Fk:getAllGenerals()) do ' +
        'if not g.hidden and not g.total_hidden then table.insert(ret, {id=g.name, name=Fk:translate(g.name), pack=Fk:translate(g.package.name)}) end end ' +
        'table.sort(ret, function(a,b) return a.id < b.id end) return ret end)()');
      candidates = JSON.parse(JSON.stringify(data || []));
      if (!Array.isArray(candidates)) candidates = [];
      generals = candidates.filter(g => availabilityCache[g.id] === true);
      if (selectedGeneral && !candidates.some(g => g.id === selectedGeneral)) selectedGeneral = "";
      checkedCount = 0;
      filterPool();
      notice = "";
      scanning = candidates.length > 0;
      if (scanning) scanDelay.restart();
      else notice = "当前房间暂无可选武将，请进入房间后重试";
    } catch (_) { generals = []; filtered = []; notice = "暂时无法读取房主将池，请稍后重试"; }
  }
  function scanBatch() {
    if (!picker.visible) return;
    const start = Date.now();
    let changed = false;
    let work = 0;
    while (checkedCount < candidates.length && work < 8) {
      const general = candidates[checkedCount++];
      if (!(general.id in availabilityCache)) {
        work++;
        if (hasVoices(general.id)) changed = true;
      }
      if (Date.now() - start >= 4) break;
    }
    if (changed) { generals = candidates.filter(g => availabilityCache[g.id] === true); filterPool(); }
    scanning = checkedCount < candidates.length;
    if (scanning) scanDelay.restart();
    else {
      generals = candidates.filter(g => availabilityCache[g.id] === true);
      filterPool();
      if (selectedGeneral && availabilityCache[selectedGeneral] !== true) selectedGeneral = "";
      if (!generals.length) notice = "房主当前将池中暂无已下载语音的武将";
    }
  }
  function filterPool() {
    const text = search.text.trim().toLowerCase();
    filtered = generals.filter(g => !text || (g.id + " " + g.name + " " + g.pack).toLowerCase().indexOf(text) >= 0);
    // Keep live delegates and the user's scroll position while detection adds
    // matching roles. Replacing an array model would reset the list each batch.
    for (let i = 0; i < filtered.length; i++) {
      const row = filtered[i];
      if (i < catalogModel.count && catalogModel.get(i).id === row.id) {
        if (catalogModel.get(i).name !== row.name) catalogModel.setProperty(i, "name", row.name);
        if (catalogModel.get(i).pack !== row.pack) catalogModel.setProperty(i, "pack", row.pack);
        continue;
      }
      let found = -1;
      for (let j = i + 1; j < catalogModel.count; j++) if (catalogModel.get(j).id === row.id) { found = j; break; }
      if (found >= 0) catalogModel.move(found, i, 1);
      else catalogModel.insert(i, row);
    }
    if (catalogModel.count > filtered.length) catalogModel.remove(filtered.length, catalogModel.count - filtered.length);
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
    for (const row of voices(selectedGeneral)) soundList.model.append(row);
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
    if (general && !hasVoices(general)) { notice = "这个武将暂无已下载的语音，已从列表排除"; filterPool(); return; }
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
    target: Config
    ignoreUnknownSignals: true
    function onEnabledResourcePacksChanged() {
      root.clearAudioCache();
      if (picker.visible) root.refreshPool();
    }
  }
  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) {
      if (["EnterRoom","ChangeRoom","EnterLobby","BackToStart"].indexOf(command) >= 0) {
        scanDelay.stop(); root.scanning = false; root.checkedCount = 0; root.candidates = [];
        root.clearAudioCache();
        root.selectedGeneral = ""; root.generals = []; root.filtered = []; catalogModel.clear(); picker.close();
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
    parent: root.Overlay.overlay || root.chatBox
    x: (parent.width - width) / 2; y: (parent.height - height) / 2
    width: Math.max(1,Math.min(640,parent.width - 16))
    height: Math.max(1,Math.min(500,parent.height - 16))
    padding: 10
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onAboutToHide: { scanDelay.stop(); root.scanning = false; }
    ColumnLayout {
      anchors.fill: parent
      RowLayout {
        Label { text:"角色语音";font.bold:true;font.pixelSize:14;Layout.fillWidth:true }
        Button { text:"重新检测";font.pixelSize:14;leftPadding:6;rightPadding:6;onClicked:root.refreshPool(true) }
        Button { text:"当前武将";font.pixelSize:14;leftPadding:6;rightPadding:6;onClicked:root.choose("") }
        Button { text:"关闭";font.pixelSize:14;leftPadding:6;rightPadding:6;onClicked:picker.close() }
      }
      TextField { id:search;Layout.fillWidth:true;font.pixelSize:14;placeholderText:"搜索有语音的角色或扩展包";onTextChanged:filterDelay.restart() }
      Label { Layout.fillWidth:true;font.pixelSize:13;wrapMode:Text.Wrap;text:root.notice || (root.scanning ? "正在检测已下载语音 " + root.checkedCount + "/" + root.candidates.length : "仅显示房主将池中有已下载语音的武将（" + root.generals.length + "）") }
      ListView {
        objectName: "roleVoiceList"
        Layout.fillWidth:true;Layout.fillHeight:true;clip:true
        model:ListModel { id:catalogModel }
        ScrollBar.vertical:ScrollBar {}
        delegate:ItemDelegate {
          required property var model
          width:ListView.view.width;height:44;font.pixelSize:14
          text:model.name + " · " + model.pack
          highlighted:root.selectedGeneral === model.id
          onClicked:root.choose(model.id)
        }
      }
    }
  }
  Timer { id:filterDelay;interval:150;onTriggered:root.filterPool() }
  Timer { id:scanDelay;interval:1;onTriggered:root.scanBatch() }
  Component.onCompleted: { soundList.delegate = voiceDelegate; installed = true; }
}
