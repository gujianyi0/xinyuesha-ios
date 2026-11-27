// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Fk

Item {
  id: features
  required property var owner
  property bool hapticsEnabled: false
  property string settingsError: ""
  property var lastHapticAt: ({})
  property bool gameEnded: false
  readonly property bool mobile: Cpp.os === "Android" || Cpp.os === "iOS"
  readonly property bool hapticsSupported: mobile && typeof Backend.playGameHaptic === "function"
  readonly property var scene: owner.currentScene
  onSceneChanged: { lastHapticAt = ({}); gameEnded = false; Qt.callLater(features.attachIndications); }

  function loadSettings() {
    try {
      const value = JSON.parse(Backend.readFileFromAssets("function-settings.json") || "{}");
      hapticsEnabled = value.haptics === true;
    } catch (_) { settingsError = "功能设置读取失败，原文件已保留"; }
  }
  function setHapticsEnabled(value) {
    try {
      const data = JSON.parse(Backend.readFileFromAssets("function-settings.json") || "{}");
      if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("Invalid settings");
      data.haptics = !!value;
      if (!Backend.writeFileToAssets("function-settings.json", JSON.stringify(data))) throw new Error("Write failed");
      hapticsEnabled = !!value;
      settingsError = "";
      return true;
    } catch (_) { settingsError = "功能设置保存失败，请重试"; return false; }
  }
  function haptic(kind, player) {
    const self = typeof Self !== "undefined" ? Self : null;
    const win = features.Window.window;
    if (!hapticsEnabled || !hapticsSupported || gameEnded || !scene || !scene.visible ||
        !win || !win.visible || !win.active || !owner.clientContext ||
        Config.replaying || Config.observing || !self || !(Number(self.id)>0) ||
        Number(player)!==Number(self.id) || ["damage","lose-hp","turn"].indexOf(kind)<0) return;
    const now = Date.now();
    if (now - (lastHapticAt[kind] || 0) < 100) return;
    lastHapticAt[kind] = now;
    Backend.playGameHaptic(kind);
  }
  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) {
      if (command === "LogEvent" && data && data.type === "Damage" && Number(data.damageNum)>0)
        features.haptic("damage", data.to);
      else if (command === "Fk.GameHaptic" && data) features.haptic(data.kind, data.player);
      else if (["EnterLobby","BackToStart","GameOver"].indexOf(command)>=0) {
        features.lastHapticAt = ({}); features.gameEnded = true;
      } else if (command === "StartGame") features.gameEnded = false;
    }
  }
  Component.onCompleted: { loadSettings(); Qt.callLater(features.ensureBundledPacks); }
  Connections {
    target: features.owner
    ignoreUnknownSignals: true
    function onSettingsReadyChanged() { if (features.owner.settingsReady) features.ensureBundledPacks(); }
  }
  function ensureBundledPacks() {
    // Android has its separately verified Java installer. Desktop/iOS builds
    // expand the same pinned archives before packaging, never from game code.
    if (Cpp.os === "Android" || !owner || !("settingsReady" in owner) || !owner.settingsReady ||
        typeof Backend.readJsonObjectFromFile !== "function" || typeof Backend.exists !== "function") return;
    const catalog=Backend.readJsonObjectFromFile("card-counter/included-visual-packs.json");
    if (!catalog || catalog.schema!==1 || !catalog.bundleId || !catalog.packs) return;
    const packs=Array.from(catalog.packs);
    try {
      const state=JSON.parse(Backend.readFileFromAssets("bundled-v1-state.json") || "{}");
      if (state.bundleId===catalog.bundleId) return;
      const previous=state.packIds || [], enabled=Array.from(Config.enabledResourcePacks || []);
      for (const pack of packs) {
        if (!Backend.exists("resource_pak/"+pack.id+"/"+pack.requiredFile)) {
          settingsError="内置资源未准备完整，请重新启动后再试"; return;
        }
        // A future update must not re-enable a pack the user had disabled.
        if (previous.indexOf(pack.id)<0 && enabled.indexOf(pack.id)<0) enabled.push(pack.id);
      }
      Config.enabledResourcePacks=enabled;
      Config.saveConf();
      if (!Backend.writeFileToAssets("bundled-v1-state.json",JSON.stringify({bundleId:catalog.bundleId,packIds:packs.map(p=>p.id)})))
        settingsError="资源启用状态未保存，请检查存储空间";
    } catch (_) { settingsError="资源启用记录读取失败，原文件已保留"; }
  }

  function adaptProfile(profile) {
    if (!mobile && !("directionalLuckEnabled" in owner)) return;
    if (Array.from(profile.children || []).some(c => c.objectName === "counterFunctionSettingsMarker")) return;
    const children = Array.from(profile.children || []);
    const tabs = children.find(c => c.model && typeof c.model.get === "function" &&
      c.model.count === 5 && c.model.get(4).name === "UI settings");
    const pages = children.find(c => typeof c.addItem === "function" && c.count === 5 && "orientation" in c);
    if (!tabs || !pages) return;
    const page = settingsPage.createObject(pages);
    if (!page) return;
    pages.addItem(page);
    tabs.model.append({name:"功能设置"});
    settingsMarker.createObject(profile);
  }
  Component { id: settingsMarker; Item { objectName:"counterFunctionSettingsMarker" } }
  Component {
    id: settingsPage
    ScrollView {
      contentWidth: availableWidth
      ColumnLayout {
        width: parent.width
        spacing: 12
        Label { text:"功能设置";font.pixelSize:24;font.bold:true;Layout.margins:16 }
        Switch {
          objectName:"directionalLuckEnabledSwitch"
          visible: "directionalLuckEnabled" in features.owner
          text:"定向刷牌"
          checked: visible && features.owner.directionalLuckEnabled
          onToggled: features.owner.setDirectionalLuckEnabled(checked)
        }
        Label {
          visible: "directionalLuckEnabled" in features.owner
          text:"开启后，在允许刷牌的询问期间显示定向刷牌面板。"
          Layout.fillWidth:true;Layout.leftMargin:16;Layout.rightMargin:16;wrapMode:Text.Wrap
        }
        Switch {
          objectName:"gameHapticsSwitch"
          visible: features.mobile
          text:"对局震动提醒"
          enabled: features.hapticsSupported
          checked: features.hapticsEnabled
          onToggled: if (!features.setHapticsEnabled(checked)) checked=features.hapticsEnabled
        }
        Label {
          visible: features.mobile
          text:features.hapticsSupported ? "仅自己受伤、失去体力或回合开始时提醒；默认关闭，遵循系统触感设置。" : "此版本暂不支持震动提醒。"
          Layout.fillWidth:true;Layout.leftMargin:16;Layout.rightMargin:16;wrapMode:Text.Wrap
        }
        Button {
          text:"奶杀动皮"
          visible:typeof features.owner.openNaishaSettings === "function"
          onClicked:features.owner.openNaishaSettings()
        }
        Label {text:features.settingsError;visible:text!=="";color:"#c54040";Layout.margins:16}
        Label {text:"functionSettingsError" in features.owner ? features.owner.functionSettingsError : "";visible:text!=="";color:"#c54040";Layout.margins:16}
      }
    }
  }

  // Change only IME presentation. Stock accepted() still commits and sends the
  // chat exactly once, including text submitted by a composing input method.
  function adaptChat(chat) {
    const pending = [chat];
    while (pending.length) {
      const item = pending.pop();
      if (!item) continue;
      if ("maximumLength" in item && item.maximumLength===300 && "accepted" in item && "inputMethodHints" in item)
        item.EnterKey.type = Qt.EnterKeySend;
      else if (item.children) pending.push(...Array.from(item.children));
    }
  }

  function indicationPoint(room, id) {
    // Dashboard includes the whole hand area. Both directions must use the
    // player's actual photo; only older UIs without that photo use Dashboard.
    let item = typeof room.getPhoto === "function" ? room.getPhoto(id) : null;
    if (!item && typeof room.getPhotoOrDashboard === "function") item = room.getPhotoOrDashboard(id);
    if (!item) return null;
    return room.mapFromItem(item, item.width/2, item.height/2);
  }
  property var stockLineComponent: null
  function showIndication(room, from, targets) {
    const start = indicationPoint(room, from);
    if (!start) return;
    const ends = [];
    for (const id of targets) {
      if (id === from) continue;
      const end = indicationPoint(room, id);
      if (end) ends.push(end);
    }
    if (!ends.length) return;
    const artwork = typeof owner.targetLineArtwork === "function" ? owner.targetLineArtwork() : "";
    if (artwork && typeof owner.showLightTargetLine === "function") {
      owner.showLightTargetLine(room, from, targets, artwork);
      return;
    }
    if (!stockLineComponent) stockLineComponent = Qt.createComponent("LunarLtk.Components", "IndicatorLine");
    if (stockLineComponent.status !== Component.Ready) return;
    const line = stockLineComponent.createObject(room, {start:start,end:ends,color:"#96943D"});
    if (line) { line.finished.connect(line.destroy); line.running = true; }
  }
  function attachIndications() {
    const room = scene;
    if (!room || typeof room.addCallback !== "function" || typeof room.doAnimate !== "function" ||
        typeof room.getPhotoOrDashboard !== "function") return;
    room.addCallback("Animate", function(sender, data) {
      if (!data || data.type !== "Indicate" || !data.to || typeof data.to.length !== "number") { room.doAnimate(sender,data); return; }
      for (const targets of data.to) {
        if (!targets || !targets.length) continue;
        features.showIndication(room, data.from, [targets[0]]);
        if (targets.length>1) features.showIndication(room, targets[0], targets.slice(1));
      }
    });
  }
}
