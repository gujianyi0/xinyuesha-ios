// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQml.Models
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import Fk
import LunarLtk
Item {
  id: host
  objectName: "fkCounterHost"
  FeedbackFeatures { id: feedbackFeatures; objectName: "feedbackFeatures"; owner: host }
  ResourcePackClient {id:resourcePackClient;owner:host}
  readonly property var resourcePackDownloads:resourcePackClient
  NaishaSkins {id:naishaSkins;owner:host}
  function openNaishaSettings() {naishaSkins.openSettings();}
  property var currentScene: null
  property string revealFocusSkill: ""
  property var arrangementBoxes: []
  // Use the stock double-tap signal and the same profile action as long press.
  // Model/photo bindings cover delayed creation and replacement without polling.
  Instantiator {
    model: host.currentScene && host.currentScene.dataModel && host.currentScene.dataModel.players || []
    delegate: Connections {
      required property var modelData
      readonly property var photo: modelData && modelData.photoItem || null
      target: photo
      ignoreUnknownSignals: true
      function onPhotoChanged() { Qt.callLater(host.syncKnownHandBadges); }
      function onVisibleChanged() { Qt.callLater(host.syncKnownHandBadges); }
      function onDoubleClicked(card) {
        if (photo && photo.visible && typeof photo.rightClicked === "function") photo.rightClicked();
      }
    }
  }
  onCurrentSceneChanged: { Qt.callLater(host.setUpLightTargetLine); cancelPresentQueue(); cancelTenyearCombos(); revealFocusSkill=""; releaseGuanNingEffects(); syncBackgroundChatShortcut(); Qt.callLater(host.adaptPlayerDetail); }
  readonly property var backgroundChatScene: waitingRoomScene && waitingRoomScene.visible ? waitingRoomScene : currentScene
  onBackgroundChatSceneChanged: syncBackgroundChatShortcut()
  property var backgroundChatShortcut: null
  Component {
    id: backgroundChatComponent
    MouseArea {
      objectName: "roomBackgroundChatShortcut"
      required property var scene
      anchors.fill: parent
      // Only input left unhandled by the room's cards and controls reaches us.
      z: -1
      acceptedButtons: Qt.LeftButton
      enabled: scene.visible && !(scene.infoPopup && scene.infoPopup.visible) &&
        !scene.popupItem && !scene.agItem && !(scene.areaHandler && scene.areaHandler.visible) && !(host.popup && host.popup.visible)
      property double lastBackgroundTapAt: 0
      property point lastBackgroundTap: Qt.point(0,0)
      property bool longPressCommitted: false
      property bool doubleTapPending: false
      property bool moved: false
      property real downX: 0
      property real downY: 0
      onPressed: mouse => {
        longPressCommitted = false; doubleTapPending = false; moved = false;
        downX = mouse.x; downY = mouse.y;
      }
      onDoubleClicked: mouse => {
        doubleTapPending = lastBackgroundTapAt > 0 &&
          Date.now()-lastBackgroundTapAt <= Qt.styleHints.mouseDoubleClickInterval &&
          Math.abs(mouse.x-lastBackgroundTap.x) <= Qt.styleHints.startDragDistance &&
          Math.abs(mouse.y-lastBackgroundTap.y) <= Qt.styleHints.startDragDistance;
        moved = false;
        downX = mouse.x; downY = mouse.y;
      }
      onPositionChanged: mouse => {
        if (Math.abs(mouse.x-downX) > Qt.styleHints.startDragDistance ||
            Math.abs(mouse.y-downY) > Qt.styleHints.startDragDistance) moved = true;
      }
      onPressAndHold: {
        if (scene !== host.waitingRoomScene || moved) return;
        longPressCommitted = true; doubleTapPending = false;
        Mediator.notify(scene, "IWantToChat");
      }
      onReleased: {
        if (doubleTapPending && !moved && !longPressCommitted) Mediator.notify(scene, "IWantToChat");
        if (!doubleTapPending && !moved && !longPressCommitted) {
          lastBackgroundTapAt = Date.now(); lastBackgroundTap = Qt.point(downX,downY);
        } else lastBackgroundTapAt = 0;
        doubleTapPending = false;
      }
      onCanceled: { doubleTapPending = false; lastBackgroundTapAt = 0; }
      onEnabledChanged: if (!enabled) { doubleTapPending = false; lastBackgroundTapAt = 0; }
    }
  }
  function syncBackgroundChatShortcut() {
    const scene = backgroundChatScene;
    const previous = backgroundChatShortcut;
    backgroundChatShortcut = null;
    try {
      if (previous && previous.parent === scene) { backgroundChatShortcut=previous; return; }
      if (previous) { previous.enabled=false; previous.objectName=""; previous.destroy(); }
    } catch (_) { /* A destroyed scene can leave a stale QML wrapper. */ }
    if (!scene) return;
    if (scene.children.some(c => c.objectName === "roomBackgroundChatShortcut")) return;
    backgroundChatShortcut = backgroundChatComponent.createObject(scene, {scene:scene});
  }
  function disposeRoomItem(item) {
    try { if (item && typeof item.destroy === "function") item.destroy(); }
    catch (_) { /* A QML var can retain a wrapper after its native parent dies. */ }
  }
  Component.onDestruction: { if (waitingPresentBar) waitingPresentBar.destroy(); cancelTenyearCombos(); disposeRoomItem(backgroundChatShortcut); releaseGuanNingEffects(); disposeRoomItem(guanNingPreview); }
  readonly property var detailPopup: currentScene && currentScene.infoPopup || null
  Connections {
    target: host.detailPopup
    ignoreUnknownSignals: true
    function onItemChanged() { Qt.callLater(host.adaptPlayerDetail); visibleCardCapture.restart(); }
    function onVisibleChanged() { if (host.detailPopup.visible) visibleCardCapture.restart(); }
  }
  Connections {
    target: host.detailPopup && host.detailPopup.item || null
    ignoreUnknownSignals: true
    function onIdsChanged() { visibleCardCapture.restart(); }
  }
  Component {
    id: arrangementCaptureComponent
    Connections {
      objectName: "counterArrangementCapture"
      required property var box
      target: box.dataModel
      ignoreUnknownSignals: true
      // Stock replyToServer clears popupItem before later accepted handlers.
      // Keep this connection bound to the box until its deferred destruction.
      function onAccepted() { host.rememberArrangement(box); }
    }
  }
  Connections {
    target: host.currentScene
    ignoreUnknownSignals: true
    function onVisibleChanged() { if (!host.currentScene.visible) {host.cancelPresentQueue();host.cancelTenyearCombos();} }
  }
  Connections {
    target: host.Window.window
    function onActiveChanged() { if (!host.Window.window.active) {host.cancelPresentQueue();} }
  }
  Connections {
    target: Config
    ignoreUnknownSignals: true
    function onReplayingChanged() { if (Config.replaying) {host.cancelPresentQueue();} }
    function onEnabledResourcePacksChanged() { host.cancelTenyearCombos(); }
    function onBanChangeSkinChanged() { if (Config.banChangeSkin) host.cancelTenyearCombos(); }
  }
  readonly property var activeRoomScene: Ltk.roomScene || null
  onActiveRoomSceneChanged: Qt.callLater(host.syncScene)
  property var popup: null
  property var deckHit: null
  property var deckItem: null
  property string lastError: ""
  property var clientContext: typeof ClientInstance !== "undefined" ? ClientInstance : null
  property bool bootstrapReady: false
  property bool settingsReady: false
  function prepareSkinMenu(model) {
    if (!model || typeof model.get !== "function" || typeof model.setProperty !== "function" || model.count > 512) return;
    for (let i=0; i<model.count; i++) {
      const row=model.get(i);
      if (row.qml && row.qml.uri === "LunarLtk.Pages" && row.qml.name === "SkinSetting")
        model.setProperty(i,"qml",{url:"card-counter/SkinSetting.qml"});
      if (row.pages) prepareSkinMenu(row.pages);
    }
  }
  // Follow the stock StackView without walking its full object tree each second.
  property var navigationRoot: null
  readonly property var navigationStack: navigationRoot
    ? navigationRoot.children.find(c => c && "currentItem" in c && "depth" in c && typeof c.get === "function") || null : null
  readonly property var navigationPage: navigationStack ? navigationStack.currentItem : null
  onNavigationRootChanged: { requestCompatibility(); Qt.callLater(host.installHomeReset); }
  onNavigationPageChanged: requestCompatibility()
  property var homeResetRoot: null
  property var pendingHomeResetRoot: null
  function installHomeReset() {
    const root = navigationRoot;
    if (!root || root === homeResetRoot || typeof root.addCallback !== "function" ||
        typeof root.tryUpdatePackage !== "function" || !navigationStack) return;
    homeResetRoot = root;
    root.addCallback("BackToStart", function(sender, data) {
      if (host.navigationRoot !== root) return;
      host.pendingHomeResetRoot = root;
      host.finishHomeReset();
    });
    resetDisconnectedHome();
  }
  function finishHomeReset() {
    const root = pendingHomeResetRoot, stack = navigationStack;
    if (!root || root !== navigationRoot || !stack || stack.busy) return;
    pendingHomeResetRoot = null;
    // StackView rejects a pop during another transition. Wait for it to finish,
    // then do one immediate pop rather than overlapping several animated pops.
    if (stack.depth > 1) stack.pop(stack.get(0), StackView.Immediate);
    root.busy = false;
    resetDisconnectedHome();
    root.tryUpdatePackage();
  }
  function resetDisconnectedHome() {
    const stack = navigationStack;
    if (clientContext || !stack || stack.depth !== 1) return;
    const home = stack.currentItem;
    if (!home || !("serverDialog" in home)) return;
    // Init survives while online. Its join-server panel also survives unless
    // explicitly closed, and intercepts the home buttons after logout.
    const loader = home.serverDialog;
    const panel = loader && loader.parent;
    if (panel && typeof panel.hide === "function") {
      panel.hide();
      panel.visible = false;
    }
    home.enabled = true;
    if (navigationRoot) navigationRoot.busy = false;
    for (const name of ["consoleStartRequested", "observing", "replaying"])
      if (name in Config) Config[name] = false;
    // No local account/favorite/package configuration is changed or saved.
  }
  Connections {
    target: host.navigationStack
    ignoreUnknownSignals: true
    function onBusyChanged() {
      if (!host.navigationStack.busy) { host.finishHomeReset(); host.requestCompatibility(); }
    }
  }
  Connections {
    target: host.Overlay.overlay
    function onChildrenChanged() { overlayAdapt.restart(); }
  }
  function requestCompatibility() { if (settingsReady) pageAdapt.restart(); }
  Timer {
    id: pageAdapt; interval: 32
    onTriggered: {
      if (host.activeRoomScene) return;
      const window = host.Window.window;
      host.refreshCompatibility(host.navigationPage || host.navigationRoot || (window ? window.contentItem : null));
    }
  }
  Timer {
    id: overlayAdapt; interval: 32
    onTriggered: if (host.settingsReady && host.Overlay.overlay) host.refreshCompatibility(host.Overlay.overlay)
  }
  Connections {
    target: Backend
    ignoreUnknownSignals: true
    function onBackgroundPicked(key, url, error) {
      if (url && ["lobbyBg","roomBg","ladyImg"].indexOf(key)>=0) { Config[key]=url; backgroundSave.restart(); }
      else if (error && typeof App!=="undefined" && App.showToast) App.showToast(error);
    }
  }
  property var photoLocations: []
  property bool hideTitles: false
  property bool preferencesLoaded: false
  property bool directionalLuckEnabled: true
  property string functionSettingsError: ""
  function setDirectionalLuckEnabled(enabled) {
    let features;
    try {
      features = JSON.parse(Backend.readFileFromAssets("function-settings.json") || "{}");
      if (!features || typeof features !== "object" || Array.isArray(features)) throw new Error("Invalid settings");
    } catch (_) { functionSettingsError = "功能设置读取失败，原文件已保留"; return false; }
    features.directionalLuck = !!enabled;
    if (!Backend.writeFileToAssets("function-settings.json", JSON.stringify(features))) {
      functionSettingsError = "设置保存失败，请重试";
      return false;
    }
    directionalLuckEnabled = !!enabled;
    functionSettingsError = "";
    if (!directionalLuckEnabled && luckPanel) {
      luckPanel.stopAuto("定向刷牌已关闭");
      disposeRoomItem(luckPanel);
      luckPanel = null;
    }
    return true;
  }
  function adaptFunctionSettings(profile) { feedbackFeatures.adaptProfile(profile); }

  property var titleBadges: []
  property var adaptedControls: []
  // Public hand knowledge is kept by counter.lua. Mirror only confirmed
  // opponent cards onto the stock player photo so the information is visible
  // without opening the counter panel.
  property var knownHandBadges: []
  property var knownHandCounts: ({})
  property string knownHandPayload: ""
  property var guanNingSkinStates: []
  property alias roleVoiceCache: roleVoiceCacheState
  QtObject {id:roleVoiceCacheState;property var entries:({})}
  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) {
      handkill.route(command, data);
      if (!host.routeLightComboBanner(command, data)) host.routeGuanNingAction(command, data);
      if (command === "BackToStart") host.roleVoiceCache.entries = {};
      if (["EnterRoom","EnterLobby","BackToStart"].indexOf(command)>=0) host.revealFocusSkill="";
      if (command === "MoveFocus") {
        const self=Lua.selfPlayer;
        host.revealFocusSkill=self && data && Array.from(data[0] || []).indexOf(self.id)>=0 ? String(data[1] || "") : "";
      }
    }
  }
  property int deckSearchTicks: 0
  onSettingsReadyChanged: if (settingsReady && !preferencesLoaded) {
    try {
      const data = JSON.parse(Backend.readFileFromAssets("client-ui.json") || "{}");
      hideTitles = data.hideTitles === true;
      const features = JSON.parse(Backend.readFileFromAssets("function-settings.json") || "{}");
      directionalLuckEnabled = features.directionalLuck !== false;
      preferencesLoaded = true;
      requestCompatibility();
    } catch (_) { console.warn("[ClientUI] preferences unreadable; preserving file"); }
  }
  function setHideTitles(value) {
    const payload = JSON.stringify({hideTitles: !!value});
    if (!preferencesLoaded || !Backend.writeFileToAssets("client-ui.json", payload)) return false;
    hideTitles = !!value; refreshCompatibility(); return true;
  }
  // Only enabled visual packs can supply images. Code and event routing remain bundled.
  function visualFileExists(path) {
    // Fs may retain negative lookups from before an in-session download.
    // The bundled backend checks the current app directory on each call.
    if (typeof Backend !== "undefined" && typeof Backend.exists === "function")
      return Backend.exists(path);
    return Fs.exists(path);
  }
  function lightEffectImage(name) {
    if (typeof Config === "undefined" || typeof Fs === "undefined") return "";
    if (name === "known-hand") return Qt.resolvedUrl("known-hand.png");
    const path = "/packages/freekill-core/image/xinyuesha-light/" + name + ".png";
    for (const pack of Config.enabledResourcePacks || []) {
      const candidate = Cpp.path + "/resource_pak/" + pack + path;
      if (visualFileExists(candidate)) return candidate;
    }
    return "";
  }
  Component { id: lightTargetLine; LightTargetLine {} }
  HandkillRouter { id: handkill; owner: host }

  property var tenyearComboComponent: null
  property var tenyearComboItem: null
  property var tenyearComboQueue: []
  property string tenyearComboLastKey: ""
  property double tenyearComboLastAt: 0
  function tenyearComboResource(general) {
    const match = /^ty_wei__(zhangliao|lvbu|machao|mateng)$/.exec(String(general));
    if (!match) return "";
    const relative = "/packages/freekill-core/image/xinyuesha-tenyear/combo/wei" + match[1] + "_jineng";
    for (const pack of Config.enabledResourcePacks || []) {
      const base = Cpp.path + "/resource_pak/" + pack + relative;
      if (visualFileExists(base + ".atlas") && visualFileExists(base + ".skel")) return base;
    }
    return "";
  }
  function cancelTenyearCombos() {
    tenyearComboQueue = [];
    tenyearComboLastKey = "";
    tenyearComboLastAt = 0;
    const item = tenyearComboItem;
    tenyearComboItem = null;
    if (item) { item.visible = false; disposeRoomItem(item); }
  }
  function startNextTenyearCombo() {
    if (tenyearComboItem || !tenyearComboQueue.length) return;
    if (!currentScene || !currentScene.visible || Config.banChangeSkin) { cancelTenyearCombos(); return; }
    const request = tenyearComboQueue.shift();
    const base = tenyearComboResource(request.general);
    if (!base) { Qt.callLater(host.startNextTenyearCombo); return; }
    if (!tenyearComboComponent) tenyearComboComponent = Qt.createComponent("TenyearCombo.qml");
    if (tenyearComboComponent.status !== Component.Ready) {
      console.warn("[TenyearCombo] player unavailable: " + tenyearComboComponent.errorString());
      tenyearComboQueue = [];
      return;
    }
    const item = tenyearComboComponent.createObject(currentScene, {
      resourceBase: base, general: request.general, skillName: request.skill
    });
    if (!item) { Qt.callLater(host.startNextTenyearCombo); return; }
    tenyearComboItem = item;
    item.finished.connect(function(completed) {
      if (host.tenyearComboItem !== item) return;
      host.tenyearComboItem = null;
      item.destroy();
      Qt.callLater(host.startNextTenyearCombo);
    });
  }

  function routeLightComboBanner(command, data) {
    const room = currentScene;
    if (!room || !room.visible || Config.banChangeSkin || command !== "Animate" || !data ||
        (data.type !== "InvokeSkill" && data.type !== "InvokeUltSkill") || !data.name || data.player == null)
      return false;
    const players = room.dataModel && room.dataModel.players || [];
    const model = Array.from(players).find(p => String(p.playerid !== undefined ? p.playerid : p.id) === String(data.player));
    const photo = model && model.photoItem;
    if (!photo || !photo.visible) return false;
    const main = photo.general || model.general || "";
    const deputy = photo.deputyGeneral || model.deputyGeneral || "";
    const generals = data.type === "InvokeUltSkill" ? [data.deputy ? deputy : main] : [main, deputy];
    const general = generals.find(g => generalOwnsSkill(g, data.name) && tenyearComboResource(g));
    if (!general) return false;
    try {
      const isCombo = Lua.ev('(function() local s=Fk.skills[' + JSON.stringify(String(data.name)) + ']; return s and s:hasTag("Combo", false) == true or false end)()');
      if (isCombo !== true) return false;
    } catch (_) { return false; }
    const key = String(data.player) + ":" + general + ":" + String(data.name);
    const now = Date.now();
    if (key === tenyearComboLastKey && now - tenyearComboLastAt < 250) return true;
    tenyearComboLastKey = key;
    tenyearComboLastAt = now;
    if (tenyearComboQueue.length >= 4) return true;
    tenyearComboQueue.push({general: general, skill: String(data.name)});
    startNextTenyearCombo();
    return true;
  }

  function showLightTargetLine(room, from, targets, artwork) {
    // The stock dashboard spans the full hand area. Use the real portrait
    // when present, including the local player's portrait.
    const origin = feedbackFeatures.indicationPoint(room, from);
    if (!origin) return;
    for (const target of targets) {
      if (target === from) continue;
      const destination = feedbackFeatures.indicationPoint(room, target);
      if (!destination) continue;
      lightTargetLine.createObject(room, {origin: origin, destination: destination, imageSource: artwork,
        olOriginalFrames: String(artwork).indexOf("/ol-target-line/zhixiangxianlong.png") >= 0,
        originalFrames: String(artwork).indexOf("gold-head-frames.png") >= 0});
    }
  }
  function targetLineArtwork() {
    const ol = lightEffectImage("ol-target-line/zhixiangxianlong");
    if (ol) {
      const base = String(ol).slice(0, -4);
      // A partial download must not suppress the stock indication animation.
      if (visualFileExists(base + ".atlas") && visualFileExists(base + ".skel")) return ol;
    }
    return lightEffectImage("gold-head-frames") || lightEffectImage("gold-trail");
  }
  function setUpLightTargetLine() { feedbackFeatures.attachIndications(); }

  Component {
    id: knownHandBadgeComponent
    Rectangle {
      id: badge
      objectName: "knownHandBadge"
      required property var photo
      property var knownCards: []
      property var knownIds: []
      readonly property var stockViewer: photo && Array.from(photo.children || []).find(
        item => String(item).indexOf("HandcardViewer_QMLTYPE") === 0) || null
      // Reuse the native viewer's appearance and full-card popup, without
      // stacking a second list over the one used by Sun Wukong's 金睛.
      Binding {
        target: badge.stockViewer
        property: "visible"
        value: false
        when: badge.visible && badge.stockViewer !== null
        restoreMode: Binding.RestoreBindingOrValue
      }
      readonly property int knownCount: knownCards.length
      readonly property bool rightSide: photoBounds.x < width + 10
      property rect photoBounds: Qt.rect(0, 0, 0, 0)
      function syncPosition() {
        // mapToItem() does not establish a QML binding on the photo's x/y.
        // Refresh after layout changes and the normal knowledge update.
        if (!host.currentScene || !photo) return;
        const top = photo.mapToItem(host.currentScene, 0, 0);
        const bottom = photo.mapToItem(host.currentScene, photo.width, photo.height);
        photoBounds = Qt.rect(Math.min(top.x, bottom.x), Math.min(top.y, bottom.y),
          Math.abs(bottom.x-top.x), Math.abs(bottom.y-top.y));
      }
      width: Math.min(66, Math.max(44, photoBounds.width * 0.38))
      height: Math.min(photoBounds.height, cardNames.implicitHeight + 10)
      radius: 6
      z: 20
      color: "#CC2E2C27"
      border.color: "#A6967A"
      visible: knownCount > 0 && photo && photo.visible && !!host.currentScene && host.currentScene.visible
      opacity: photo ? photo.opacity : 1
      // Keep the side list in table coordinates, outside portrait transforms
      // and clipping. It must not become part of the skin image itself.
      x: Math.max(0, Math.min(parent.width-width,
        rightSide ? photoBounds.x+photoBounds.width+5 : photoBounds.x-width-5))
      y: photoBounds.y + (photoBounds.height-height) / 2
      Component.onCompleted: syncPosition()
      Connections {
        target: badge.photo
        function onXChanged() { badge.syncPosition(); }
        function onYChanged() { badge.syncPosition(); }
        function onWidthChanged() { badge.syncPosition(); }
        function onHeightChanged() { badge.syncPosition(); }
        function onScaleChanged() { badge.syncPosition(); }
      }
      Flickable {
        anchors.fill: parent
        anchors.margins: 5
        clip: true
        contentWidth: width
        contentHeight: cardNames.implicitHeight
        interactive: contentHeight > height
        Column {
          id: cardNames
          width: parent.width
          spacing: 2
          Repeater {
            model: badge.knownCards.slice(0, 4)
            delegate: Text {
              required property string modelData
              width: cardNames.width
              text: modelData
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WrapAnywhere
              color: "#E4D5A0"
              font.pixelSize: 16
            }
          }
          Text {
            visible: badge.knownCount > 4
            height: visible ? implicitHeight : 0
            width: cardNames.width
            text: "…"
            color: "#E4D5A0"
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
      TapHandler {
        enabled: badge.knownIds.length > 0
        onTapped: host.openKnownHands(badge.knownIds)
      }
    }
  }
  function knownHandKey(model) {
    if (!model) return "";
    const id = model.playerid !== undefined ? model.playerid : model.id;
    return id === undefined || id === null ? "" : String(id);
  }
  function readKnownHands() {
    if (typeof ClientInstance === "undefined" || !ClientInstance) return {};
    try {
      const value = Lua.ev('(function() if not FkCardCounterV2 then FkCardCounterV2 = dofile("card-counter/counter.lua") end return FkCardCounterV2.current("slash") end)()');
      const byOwner = ({}), rows = value && value.knowledge && value.knowledge.hands || [];
      for (const row of rows) {
        if (!row || row.uncertain === true) continue;
        const key = row.ownerId === undefined || row.ownerId === null ? "" : String(row.ownerId);
        if (!key) continue;
        if (!byOwner[key]) byOwner[key] = [];
        byOwner[key].push({name:String(row.name || row.key || "明牌"), id:Number(row.id || 0)});
      }
      return byOwner;
    } catch (_) { return {}; }
  }
  function openKnownHands(ids) {
    const scene = currentScene;
    if (!scene || typeof scene.showInfoPopup !== "function") return;
    const live = readKnownHands();
    // Revalidate after a move; a stale badge must never reopen expired cards.
    const confirmed = new Set();
    for (const owner of Object.keys(live))
      for (const row of live[owner]) confirmed.add(row.id);
    const visibleIds = ids.filter(id => id > 0 && confirmed.has(id));
    if (!visibleIds.length) return;
    scene.showInfoPopup(Qt.createComponent("LunarLtk.Pages.InfoPopups", "ViewPile"), {
      name:"hand_card", ids:visibleIds, additional_prop:{selectable:true, markVisible:true}
    });
  }
  function syncKnownHandBadges() {
    const scene = currentScene;
    const players = scene && scene.dataModel && scene.dataModel.players || [];
    const hands = readKnownHands();
    const payload = JSON.stringify(hands);
    if (knownHandPayload !== payload) {
      knownHandPayload = payload;
      const counts = ({});
      for (const key of Object.keys(hands)) counts[key] = hands[key].length;
      knownHandCounts = counts;
    }
    const livePhotos = Array.from(players).map(model => model && model.photoItem).filter(Boolean);
    knownHandBadges = knownHandBadges.filter(function(badge) {
      try {
        if (badge && badge.parent && livePhotos.indexOf(badge.photo) >= 0) return true;
      } catch (_) {}
      disposeRoomItem(badge);
      return false;
    });
    for (const model of Array.from(players)) {
      const photo = model && model.photoItem;
      if (!photo) continue;
      let badge = knownHandBadges.find(b => b.photo === photo);
      if (!badge) {
        badge = knownHandBadgeComponent.createObject(scene, {photo: photo});
        if (badge) knownHandBadges.push(badge);
      }
      const rows = hands[knownHandKey(model)] || [];
      const cards = rows.map(row => row.name), ids = rows.map(row => row.id).filter(id => id > 0);
      if (badge) {
        if (JSON.stringify(badge.knownCards) !== JSON.stringify(cards)) badge.knownCards = cards;
        if (JSON.stringify(badge.knownIds) !== JSON.stringify(ids)) badge.knownIds = ids;
      }
      if (badge) badge.syncPosition();
    }
    triggerGuanNingSkinEffects(players);
  }
  property var guanNingPluginComponent: null
  property var guanNingPreview: null
  property var guanNingSkillOwners: ({})
  function releaseGuanNingEffects() {
    for (const state of guanNingSkinStates || []) disposeRoomItem(state.effect);
    guanNingSkinStates = [];
    guanNingSkillOwners = ({});
  }
  function guanNingPluginUrl(file) {
    const base = String(Cpp.path || "").replace(/\/$/, "");
    return base + "/card-counter/guanning/" + file;
  }
  function guanNingResourceRoot() {
    if (typeof Fs === "undefined") return "";
    for (const pack of Config.enabledResourcePacks || []) {
      const root = Cpp.path + "/resource_pak/" + pack + "/packages/freekill-core/image/xinyuesha-tenyear/guanning/8195001/";
      if (visualFileExists(root + "chuchang2.skel")) return root;
    }
    return "";
  }
  function loadGuanNingPlugin() {
    if (!guanNingResourceRoot()) return null;
    if (guanNingPluginComponent && guanNingPluginComponent.status === Component.Ready) return guanNingPluginComponent;
    if (typeof Fs === "undefined" || !Fs.resolveFile(guanNingPluginUrl("GuanNingActions.qml"))) return null;
    guanNingPluginComponent = Qt.createComponent(guanNingPluginUrl("GuanNingActions.qml"));
    if (guanNingPluginComponent.status !== Component.Ready) {
      console.warn("[GuanNingActions] resource component: " + guanNingPluginComponent.errorString());
      guanNingPluginComponent = null; return null;
    }
    return guanNingPluginComponent;
  }
  function findGuanNingStockArea(photo, general, skinName) {
    const pending = Array.from(photo.children || []), seen = new Set();
    for (let i=0; i<pending.length && i<128; i++) {
      const item = pending[i];
      if (!item || seen.has(item)) continue;
      seen.add(item);
      if ("skelData" in item && item.general === general && item.skinName === skinName) return item;
      if (item.children) pending.push(...Array.from(item.children));
      if (item.item) pending.push(item.item);
    }
    return null;
  }
  function triggerGuanNingSkinEffects(players) {
    if (Config.banChangeSkin || !guanNingResourceRoot()) { releaseGuanNingEffects(); return; }
    const active = [];
    for (const model of Array.from(players || [])) {
      const photo = model && model.photoItem;
      if (!photo) continue;
      for (const side of ["main", "deputy"]) {
        const general = String(side === "main" ? photo.general || model.general || "" : photo.deputyGeneral || model.deputyGeneral || "");
        const skin = side === "main" ? photo.skinSource || model.skin : photo.deputySkinSource || model.deputySkin;
        const name = String(skin && skin.name || "");
        if (!isGuanNingGeneral(general) || /\.(jpg|jpeg|png|webp)$/i.test(name) || !/墨韵荷香|guanning_1(?:__daiji)?\.mp4/i.test(name)) continue;
        const signature = general + ":" + name;
        const old = guanNingSkinStates.find(s => s.photo === photo && s.signature === signature && s.effect);
        if (old) { active.push(old); continue; }
        const component = loadGuanNingPlugin();
        if (!component) continue;
        const effect = component.createObject(photo, {photo:photo, scene:currentScene, general:general, skinName:name,
          stockArea:findGuanNingStockArea(photo,general,name), resourceRoot:guanNingResourceRoot()});
        if (effect) active.push({photo:photo, signature:signature, effect:effect});
      }
    }
    for (const old of guanNingSkinStates) if (old.effect && !active.some(s => s.effect === old.effect)) disposeRoomItem(old.effect);
    guanNingSkinStates = active;
  }
  function openGuanNingPreview() {
    if (guanNingPreview) { guanNingPreview.open(); return true; }
    if (typeof Fs === "undefined" || !Fs.resolveFile(guanNingPluginUrl("GuanNingPreview.qml"))) return false;
    const component = Qt.createComponent(guanNingPluginUrl("GuanNingPreview.qml"));
    if (component.status !== Component.Ready) { console.warn(component.errorString()); return false; }
    const window = host.Window.window;
    guanNingPreview = component.createObject(window.contentItem,{resourceRoot:guanNingResourceRoot()});
    if (!guanNingPreview) return false;
    guanNingPreview.open(); return true;
  }
  function isGuanNingGeneral(name) {
    return /^(guanning|guan_ning|guan-ning|管宁|n_guanning)$|__guanning$/i.test(String(name || ""));
  }
  function canonicalSkillName(name) {
    if (!name) return "";
    try {
      // SkillSkeleton generates names such as #zhongao_4_trig. Resolve the
      // registered engine relationship rather than stripping name patterns.
      const result=Lua.ev('(function() local s=Fk.skills['+JSON.stringify(String(name))+']; if not s then return nil end return (s.skeleton and s.skeleton.name) or (s.main_skill and s.main_skill.name) or s.name end)()');
      if (typeof result==="string" && result.length) return result;
    } catch (_) {}
    return String(name);
  }
  function generalOwnsSkill(general, name) {
    if (!name) return false;
    name=canonicalSkillName(name);
    const key=general+":"+String(name);
    if (guanNingSkillOwners[key]!==undefined)return guanNingSkillOwners[key];
    let owns=false;
    try {
      // Keep table membership on the Lua side: Lua.ev may wrap tables in a
      // CBOR proxy on shipped clients, so Array.isArray is not a valid gate.
      owns=Lua.ev('(function() local g=Fk.generals['+JSON.stringify(general)+']; if not g then return false end local ok,n=pcall(function() return g:getSkillNameList(true,true) end); if not ok then return false end for _,s in ipairs(n) do if s=='+JSON.stringify(String(name))+' then return true end end return false end)()')===true;
    } catch (_) {}
    guanNingSkillOwners[key]=owns;return owns;
  }
  function routeGuanNingAction(command, data) {
    if (!currentScene || !currentScene.visible || Config.banChangeSkin || !data) return 0;
    let action = "";
    if (command === "Fk.GuanNingSkinAction" && data.action === "attack") action = "attack";
    else if (command === "Animate" && (data.type === "InvokeSkill" || data.type === "InvokeUltSkill")) action = "skill";
    if (!action || data.player === undefined || data.player === null) return 0;
    const players = currentScene.dataModel && currentScene.dataModel.players || [];
    const model = Array.from(players).find(p => String(p.playerid !== undefined ? p.playerid : p.id) === String(data.player));
    const photo = model && model.photoItem;
    if (!photo || !photo.visible) return 0;
    const generals = [String(photo.general || model.general || ""), String(photo.deputyGeneral || model.deputyGeneral || "")]
      .filter(Boolean);
    let played = 0;
    if (generals.some(host.isGuanNingGeneral)) triggerGuanNingSkinEffects(players);
    for (const general of generals) {
      if (!isGuanNingGeneral(general)) continue;
      if (data.type === "InvokeUltSkill" && general !== (data.deputy ? photo.deputyGeneral : photo.general)) continue;
      if (action === "skill" && !generalOwnsSkill(general,data.name)) continue;
      const owned = guanNingSkinStates.find(s => s.photo === photo && s.effect && s.effect.general === general);
      if (owned) { if (owned.effect.playAction(action, {targets:data.targets || [], skillName:data.name || ""})) played++; continue; }
      if (typeof photo.playSkinAction === "function" && photo.playSkinAction(action, general)) { played++; continue; }
      // The shipped older frontend has no PhotoBase.playSkinAction. Its skin
      // adapter exposes the same action protocol without changing checked core files.
      const pending = Array.from(photo.children || []), seen = new Set();
      for (let i = 0; i < pending.length && i < 128; i++) {
        const item = pending[i];
        if (!item || seen.has(item)) continue;
        seen.add(item);
        if (String(item.general || "") === general && typeof item.playAction === "function") {
          if (item.playAction(action)) played++;
          break;
        }
        if (item.children) pending.push(...Array.from(item.children));
        if (item.item) pending.push(item.item);
      }
    }
    return played;
  }
  function chatIcon(kind) {
    const shapes = {
      sound: '<path d="M3 4h18v13H11l-5 4v-4H3z" fill="white" stroke="#161616" stroke-width="1.3"/>',
      emoji: '<circle cx="12" cy="12" r="10" fill="#ffd348" stroke="#ba8822"/><ellipse cx="8.5" cy="9" rx="1.4" ry="2" fill="#35271b"/><ellipse cx="15.5" cy="9" rx="1.4" ry="2" fill="#35271b"/><path d="M6.5 14h11c-1 6-10 6-11 0" fill="#513824"/><path d="M8 14h8v2H8z" fill="white"/>',
      send: '<path d="M4 12l5 6L21 4" fill="none" stroke="white" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>',
      expand: '<path d="M2 3h13v11H9l-5 4v-4H2z" fill="white"/><path d="M20 13v9m-4-4h8" stroke="white" stroke-width="2"/>',
      collapse: '<path d="M2 3h13v11H9l-5 4v-4H2z" fill="white"/><path d="M16 18h8" stroke="white" stroke-width="2"/>'
    };
    return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'+shapes[kind]+'</svg>');
  }
  function adaptTouchLog(view) {
    // Newer cores wrap the actual vertical list in RoomGameLogEdit.
    if (!("movementStarted" in view)) {
      const pending = Array.from(view.children || []);
      while (pending.length) {
        const child = pending.pop();
        if ("movementStarted" in child && "currentIndex" in child && child.orientation === ListView.Vertical)
          host.adaptTouchLog(child);
        else if (child.children) pending.push(...Array.from(child.children));
      }
      return;
    }
    if (adaptedControls.indexOf(view)>=0) return;
    adaptedControls.push(view);
    touchLogGuard.createObject(view, {view:view});
    // LogEdit follows the last selected index, rather than the viewport. A
    // manual drag must leave that index before the next live log is appended.
    view.movementStarted.connect(function() { view.currentIndex=-1; });
    view.movementEnded.connect(function() {
      if (view.atYEnd && view.count>0) view.currentIndex=view.count-1;
    });
  }
  function adaptRoomDrawerSwipe(view) {
    if (view.count !== 3 || view.orientation !== Qt.Horizontal || !view.parent) return;
    const names = [Lua.tr("Log"), Lua.tr("Chat"), Lua.tr("PlayerList")];
    const tabs = Array.from(view.parent.children || []).find(item =>
      String(item).indexOf("ViewSwitcher_QMLTYPE") === 0 && item.model &&
      [JSON.stringify(names), JSON.stringify(names.slice(1))].indexOf(JSON.stringify(Array.from(item.model))) >= 0);
    if (!tabs || adaptedControls.indexOf(view) >= 0) return;
    // Use the existing horizontal SwipeView so nested lists retain vertical
    // drags. The stock currentIndex binding already handles tab -> page.
    const sync = roomDrawerSwipeSync.createObject(view, {view:view, tabs:tabs});
    if (sync) {
      view.interactive = Qt.binding(function() { return sync.available; });
      adaptedControls.push(view);
    }
  }
  Component {
    id: roomDrawerSwipeSync
    Connections {
      objectName: "roomDrawerSwipeSync"
      required property var view
      required property var tabs
      // Newer cores also have a two-tab logless mode with a page offset.
      // Keep its existing navigation until a full three-tab drawer is shown.
      readonly property bool available: JSON.stringify(Array.from(tabs.model || [])) ===
        JSON.stringify([Lua.tr("Log"), Lua.tr("Chat"), Lua.tr("PlayerList")])
      enabled: available
      target: view
      function onCurrentIndexChanged() {
        if (tabs.currentIndex !== view.currentIndex) tabs.currentIndex = view.currentIndex;
      }
    }
  }
  Component {
    id: touchLogGuard
    Item {
      id: guard
      objectName: "touchLogGuard"
      required property var view
      property var adaptedRows: []
      // Only inspect this ListView's live delegates when they are created.
      // Its delegate and avatar layout stay intact; no whole-page polling.
      function adaptRows() {
        adaptedRows = adaptedRows.filter(row => row && row.parent === view.contentItem);
        for (const row of Array.from(view.contentItem.children || [])) {
          if (adaptedRows.indexOf(row) >= 0) continue;
          const pending = [row], seen = new Set();
          let ready = false;
          while (pending.length) {
            const item = pending.pop();
            if (!item || seen.has(item)) continue;
            seen.add(item);
            if ("gesturePolicy" in item && "tapped" in item) {
              item.gesturePolicy = TapHandler.DragThreshold;
              item.grabPermissions = PointerHandler.ApprovesTakeOverByAnything;
              ready = true;
            }
            if ("readOnly" in item && item.readOnly && "selectByKeyboard" in item) {
              // Rich log text must not start selection/focus gestures above
              // the list. Its original text, links and avatar layout remain.
              item.enabled = false;
            }
            if (item.children) pending.push(...Array.from(item.children));
            if (item.data) pending.push(...Array.from(item.data));
          }
          if (ready) adaptedRows.push(row);
        }
      }
      // Delegates can be incubated: their visual item arrives before its
      // non-visual TapHandler. Defer until the next frame and also observe
      // content-size changes as those delayed text rows finish construction.
      Timer { id: rowAdapt; interval: 16; onTriggered: guard.adaptRows() }
      Connections {
        target: guard.view.contentItem
        function onChildrenChanged() { if (!rowAdapt.running) rowAdapt.start(); }
      }
      Connections {
        target: guard.view
        function onContentHeightChanged() { if (!rowAdapt.running) rowAdapt.start(); }
        function onMovementStarted() { guard.adaptRows(); }
        function onMovementEnded() { guard.adaptRows(); }
      }
      Component.onCompleted: adaptRows()
    }
  }
  function attachRoleVoices(chat) {
    if (adaptedControls.indexOf(chat) >= 0 || chat.isLobby) return;
    let sound = null, input = null;
    const pending = [chat];
    while (pending.length) {
      const node = pending.pop();
      if (!node) continue;
      if ("soundIdx" in node && "delegate" in node && "model" in node) sound = node;
      if (String(node).indexOf("RowLayout") >= 0 && node.children &&
          Array.from(node.children).some(c => "maximumLength" in c && "accepted" in c)) input = node;
      if (!("model" in node) && node.children) pending.push(...Array.from(node.children));
    }
    if (!sound || !input) return;
    const component = Qt.createComponent("RoleVoiceControl.qml");
    if (component.status !== Component.Ready) { console.warn(component.errorString()); return; }
    const control = component.createObject(input, {chatBox:chat, soundList:sound, cacheStore:host.roleVoiceCache});
    if (control) {
      adaptedControls.push(chat);
    }
  }
  function actionTargets() {
    const scene=presentScene;
    if (scene && scene===waitingRoomScene) {
      const players=[];
      for (let i=0;i<Math.min(scene.playerNum,scene.photoModel.count);i++) {
        const row=scene.photoModel.get(i), id=row.id;
        if (Number.isInteger(id) && id!==0 && id!==-1 && row.sealed!==true && row.screenName!=="")
          players.push({playerid:id});
      }
      return players;
    }
    const room = scene && scene.dataModel;
    return Array.from(room && room.players || []).filter(model => model &&
      Number.isInteger(model.playerid) && model.playerid !== 0 && model.playerid !== -1);
  }
  // Adapt only the newly opened stock profile. Never intercept a general's
  // rightClicked signal: that belongs to the original player-detail page.
  // FB-0DX3XM: adapt only the stock four-area player profile.
  // Keep the server/core files intact and the original vertical Flickables.
  function adaptPlayerDetailSwipe(profile) {
    if (!profile) return;
    const names = [Lua.tr("skill"), Lua.tr("$Equip"), Lua.tr("$Judge"), Lua.tr("$Hand")];
    const pending = Array.from(profile.children || []);
    while (pending.length) {
      const item = pending.pop();
      if (!item) continue;
      if (String(item).indexOf("SwipeView_QMLTYPE") === 0 && item.count === 4 &&
          item.orientation === Qt.Horizontal && item.parent) {
        const tabs = Array.from(item.parent.children || []).find(c =>
          String(c).indexOf("ViewSwitcher_QMLTYPE") === 0 && c.model &&
          JSON.stringify(Array.from(c.model)) === JSON.stringify(names));
        if (tabs && !Array.from(profile.children || []).some(c => c && c.objectName === "playerDetailSwipeSync" && c.view === item)) {
          const sync = playerDetailSwipeSync.createObject(profile, {view:item, tabs:tabs});
          if (sync) item.interactive = true;
        }
      } else if (item.children) {
        pending.push(...Array.from(item.children));
      }
    }
  }
  Component {
    id: playerDetailSwipeSync
    Item {
      id: profileSwipe
      objectName: "playerDetailSwipeSync"
      required property var view
      required property var tabs
      visible: false
      Connections {
        target: profileSwipe.view
        function onCurrentIndexChanged() {
          if (profileSwipe.tabs.currentIndex !== profileSwipe.view.currentIndex)
            profileSwipe.tabs.currentIndex = profileSwipe.view.currentIndex;
        }
      }
    }
  }
  function adaptPlayerDetail(item) {
    if (!item) item = detailPopup && detailPopup.item;
    if (!item || !("dataModel" in item) || !("finish" in item) ||
        !item.children) return;
    adaptPlayerDetailSwipe(item);
    const row = Array.from(item.children).find(c => c.children &&
      Array.from(c.children).some(b => b.text === Lua.tr("Give Flower")) &&
      Array.from(c.children).some(b => b.text === Lua.tr("Give Egg")));
    if (!row) return;
    const buttons = Array.from(row.children);
    if (Array.from(row.children).some(c => c.objectName === "allPresentActionBar")) return;
    const bar = allPresentActionBar.createObject(row, {profile:item});
    if (!bar) return;
    row.Layout.fillWidth = true;
    // Keep the row in its original ColumnLayout slot. The Flow becomes its
    // only visual child; the stock buttons retain their scope and handlers.
    const additions = Array.from(bar.children);
    for (const button of buttons) button.parent = bar;
    bar.children = buttons.concat(additions);
  }
  Component {
    id: allPresentActionBar
    Flow {
      id: bar
      objectName: "allPresentActionBar"
      required property var profile
      property alias eggButton: eggButton
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      spacing: 6
      PresentButton {id:eggButton;objectName:"presentEggButton";text:"全员砸蛋";presentKind:"Egg"}
      PresentButton {objectName:"presentFlowerButton";text:"全员送花";presentKind:"Flower"}
    }
  }
  // FB-PGYSFQ: waiting-room gifts use the stock page and avatar action panel.
  readonly property var waitingRoomCandidate: navigationPage && "gameContent" in navigationPage ? navigationPage.gameContent : null
  readonly property var waitingRoomScene: waitingRoomCandidate && "isAllReady" in waitingRoomCandidate &&
    "photoModel" in waitingRoomCandidate && typeof waitingRoomCandidate.givePresent==="function" ? waitingRoomCandidate : null
  readonly property var presentScene: waitingRoomScene && waitingRoomScene.visible ? waitingRoomScene : currentScene
  property var waitingPresentBar: null
  onPresentSceneChanged: cancelPresentQueue()
  onWaitingRoomSceneChanged: {
    if (waitingPresentBar) { waitingPresentBar.destroy(); waitingPresentBar=null; }
    if (waitingRoomScene) waitingPresentBar=waitingPresentComponent.createObject(waitingRoomScene,{scene:waitingRoomScene});
  }
  Connections {
    target: host.waitingRoomScene
    ignoreUnknownSignals: true
    function onVisibleChanged() { if (!host.waitingRoomScene.visible) host.cancelPresentQueue(); }
  }
  function waitingGiftPanel(scene) {
    const panel=scene && scene.areaHandler && scene.areaHandler.tmpItem;
    if (!panel) return null;
    const pending=[{item:panel,depth:0}];
    while (pending.length) {
      const entry=pending.pop(), item=entry.item;
      const children=Array.from(item.children || []);
      if (children.some(c=>c.text===Lua.tr("Give Flower")) && children.some(c=>c.text===Lua.tr("Give Egg"))) return panel;
      if (entry.depth<4) for (const child of children) pending.push({item:child,depth:entry.depth+1});
    }
    return null;
  }
  Component {
    id: waitingPresentComponent
    Rectangle {
      id: waitingBar
      objectName: "waitingRoomPresentActions"
      required property var scene
      readonly property var panel: host.waitingGiftPanel(scene)
      readonly property real panelX: panel ? panel.x : 0
      readonly property real panelY: panel ? panel.y : 0
      readonly property var panelParent: panel ? panel.parent : null
      readonly property point origin: panelParent ? panelParent.mapToItem(scene,panelX,panelY) : Qt.point(0,0)
      readonly property bool fitsRight: !!panel && origin.x+panel.width+width+12<=scene.width
      readonly property bool fitsLeft: origin.x>=width+12
      width: 116; height: actions.implicitHeight+12; radius: 7
      color: "#2A1F1F"; border.color: "#a68a54"
      z: scene.areaHandler ? scene.areaHandler.z+2 : 22
      visible: !!panel && scene.visible && scene.areaHandler.visible && !Config.replaying
      x: !panel ? 0 : fitsRight ? origin.x+panel.width+6 : fitsLeft ? origin.x-width-6 : Math.max(6,Math.min(scene.width-width-6,origin.x))
      y: {
        if (!panel) return 0;
        const top=fitsRight || fitsLeft ? origin.y :
          origin.y+panel.height+height+12<=scene.height ? origin.y+panel.height+6 : origin.y-height-6;
        return Math.max(6,Math.min(scene.height-height-6,top));
      }
      Column {
        id: actions
        x: 6; y: 6; width: parent.width-12; spacing: 6
        PresentButton {objectName:"waitingRoomFlowerButton";text:"全员送花";presentKind:"Flower";width:parent.width;height:36;closeWaitingPanel:true}
        PresentButton {objectName:"waitingRoomEggButton";text:"全员砸蛋";presentKind:"Egg";width:parent.width;height:36;closeWaitingPanel:true}
      }
    }
  }
  // End FB-PGYSFQ waiting-room adapter.

  property var presentQueue: []
  property var presentQueueScene: null
  property string presentQueueKind: ""
  property int presentRestSeconds: 0
  function cancelPresentQueue() {
    if (presentQueue.length) { presentRestSeconds=10; presentRest.restart(); }
    presentQueue=[]; presentQueueScene=null;
  }
  function sendNextPresent() {
    // Send the finite click snapshot in the same UI turn. The stock Chat
    // protocol broadcasts each present; there is no artificial 1.6s queue.
    while (presentQueue.length) {
      if (!presentScene || presentScene!==presentQueueScene || Config.replaying || !clientContext ||
          !presentScene.visible || (host.Window.window && !host.Window.window.active)) { cancelPresentQueue(); return; }
      const valid=actionTargets().map(p=>p.playerid);
      const pending=presentQueue.slice(); const id=pending.shift(); presentQueue=pending;
      if (valid.indexOf(id)>=0) clientContext.notifyServer("Chat",{type:2,msg:"$@"+presentQueueKind+":"+id});
    }
    presentQueueScene=null;
  }
  function sendPresent(kind) {
    if (presentRestSeconds > 0 || presentQueue.length || !presentScene || !presentScene.visible || Config.replaying || !clientContext ||
        ["Egg","Flower"].indexOf(kind)<0) return false;
    const selfId = typeof Self !== "undefined" && Self ? Self.id : 0;
    const ids = [];
    for (const p of actionTargets()) {
      const id=p.playerid;
      if (Number.isInteger(id) && id !== 0 && id !== -1 && ids.indexOf(id)<0 &&
          (kind !== "Egg" || id !== selfId)) ids.push(id);
    }
    if (!ids.length) return false;
    presentQueue=ids; presentQueueScene=presentScene; presentQueueKind=kind;
    presentRestSeconds=10; presentRest.restart();
    sendNextPresent(); return true;
  }
  Timer {id:presentRest;interval:1000;repeat:true;onTriggered:{
    host.presentRestSeconds--; if (host.presentRestSeconds <= 0) stop();
  }}
  component PresentButton: Button {
    property string presentKind
    property bool closeWaitingPanel: false
    width: implicitWidth; height: 40
    font.pixelSize: 16
    leftPadding: 8; rightPadding: 8; topInset: 0; bottomInset: 0
    enabled: !!host.presentScene && host.presentScene.visible && !Config.replaying && !!host.clientContext &&
      host.presentRestSeconds === 0 && !host.presentQueue.length
    autoRepeat: false
    background: Rectangle {radius:6;color:parent.down ? "#5C3D3D" : "#2A1F1F";border.color:"#6B4F3A";opacity:parent.enabled ? 1 : 0.35}
    contentItem: Text {text:parent.text;font:parent.font;color:"#E8D5B0";horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}
    ToolTip.visible: hovered || down
    ToolTip.text: host.presentRestSeconds>0 ? "冷却中："+host.presentRestSeconds+" 秒" :
      host.presentQueue.length ? "正在同批发送" :
      "点按向全员同批发送，砸蛋排除自己；共用 10 秒冷却"
    onClicked: {
      if (host.sendPresent(presentKind) && closeWaitingPanel && host.waitingRoomScene && host.waitingRoomScene.areaHandler)
        host.waitingRoomScene.areaHandler.closeItem();
    }
  }
  function refreshCompatibility(rootItem) {
    // Periodic whole-tree scans must never run during a match or spectating.
    if (activeRoomScene && !rootItem) return;
    const window = host.Window.window;
    if (!window) return;
    // Cache surviving controls so bindings are installed once per instance.
    titleBadges = titleBadges.filter(x => x && x.parent);
    adaptedControls = adaptedControls.filter(x => x && x.parent);
    const ios = Cpp.os === "iOS";
    let visited = 0;
    const seen = new Set();
    function scan(item, depth, serverPage, lobbyPage, chatBox) {
      if (!item || typeof item !== "object" || seen.has(item) || depth > 24 || ++visited > 12000) return;
      seen.add(item);
      if ("model" in item) host.prepareSkinMenu(item.model);
      const type = String(item);
      if (type.indexOf("ChatBox_QMLTYPE") === 0 || type.indexOf("AvatarChatBox_QMLTYPE") === 0) feedbackFeatures.adaptChat(item);
      if (type.indexOf("EditProfile_QMLTYPE") === 0) host.adaptFunctionSettings(item);
      if (ios && type.indexOf("SwipeView_QMLTYPE") === 0) host.adaptRoomDrawerSwipe(item);
      if (type.indexOf("PlayerDetail_QMLTYPE") === 0) host.adaptPlayerDetail(item);
      if (type.indexOf("AvatarChatBox_QMLTYPE") === 0 && typeof item.loadSkills === "function")
        host.attachRoleVoices(item);
      if ((Cpp.os==="Android" || Cpp.os==="iOS") &&
          (type.indexOf("LogEdit_QMLTYPE")===0 || type.indexOf("RoomGameLogEdit_QMLTYPE")===0))
        host.adaptTouchLog(item);
      serverPage = serverPage || ("selectedServer" in item && "serverListUrl" in item);
      lobbyPage = lobbyPage || ("roomModel" in item && "serverPlayerNum" in item);
      chatBox = chatBox || type.indexOf("ChatBox_QMLTYPE") === 0;
      // Overview card/general grids contain no compatibility controls. Do not
      // inspect thousands of delegates when opening these utility pages.
      if (!serverPage && !lobbyPage && "cellWidth" in item && "cellHeight" in item && "delegate" in item && "model" in item) return;
      if (serverPage && adaptedControls.indexOf(item) < 0 && "model" in item && "countChanged" in item && "contentItem" in item) {
        // Server probes populate delegates after the page is first displayed.
        item.countChanged.connect(host.requestCompatibility);
        adaptedControls.push(item);
      }
      const children = item.children ? Array.from(item.children) : [];
      if (adaptedControls.indexOf(item) < 0 && "generalCardList" in item && "draggingCard" in item && "dataModel" in item) {
        // Fit the complete selection box, including both borders and buttons.
        item.scale = Qt.binding(function() {
          return item.parent ? Math.min(1, Math.max(0.1,(item.parent.width-16)/Math.max(1,item.width)),
                                        Math.max(0.1,(item.parent.height-16)/Math.max(1,item.height))) : 1;
        });
        adaptedControls.push(item);
      }
      if (ios && adaptedControls.indexOf(item) < 0 && "suffixLoader" in item && "subTitle" in item && "contentItem" in item) {
        item.Layout.minimumHeight = Qt.binding(function() { return Math.max(60,item.implicitHeight); });
        item.Layout.preferredHeight = Qt.binding(function() { return Math.max(60,item.implicitHeight); });
        adaptedControls.push(item);
      }
      if (ios && adaptedControls.indexOf(item) < 0 && "placeholderText" in item && item.placeholderText === Lua.tr("Note")) {
        item.font.pixelSize = 16; item.topPadding = 10; item.bottomPadding = 10;
        item.Layout.minimumHeight = 44; adaptedControls.push(item);
      }
      if (adaptedControls.indexOf(item) < 0 && "nameFilters" in item && "selectedFile" in item && "currentFolder" in item) {
        function prepareDialog() {
          if ("configKey" in item) {
            if (["lobbyBg","roomBg","lady"].indexOf(item.configKey) >= 0 && ios) {
              const pictures = host.photoLocations;
              if (pictures.length) item.currentFolder = pictures[pictures.length-1];
            }
            const filters = Array.from(item.nameFilters).map(f => f.indexOf("(") >= 0 && !f.endsWith(")") ? f+")" : f);
            if (JSON.stringify(filters) !== JSON.stringify(Array.from(item.nameFilters))) item.nameFilters = filters;
          } else if (Array.from(item.nameFilters).some(f => f.indexOf("*.fk.rep") >= 0)) {
            item.currentFolder = AppPath + "/recording";
            item.nameFilters = ["新月杀录像 (*.rep)", "所有文件 (*)"];
          }
        }
        if ("configKeyChanged" in item) item.configKeyChanged.connect(prepareDialog);
        item.nameFiltersChanged.connect(prepareDialog);
        prepareDialog(); adaptedControls.push(item);
      }
      if ("title" in item && "customReady" in item &&
          children.some(c => c.objectName === "titleBackplate") && titleBadges.indexOf(item) < 0) {
        titleBadges.push(item);
        item.opacity = Qt.binding(function() { return host.hideTitles ? 0 : 1; });
      }
      if (ios && adaptedControls.indexOf(item) < 0) {
        if (serverPage && "text" in item && "elide" in item && "font" in item && item.wrapMode === Text.NoWrap) {
          item.elide = Text.ElideRight; item.maximumLineCount = 1;
          item.Layout.minimumWidth = 0;
          if (item.parent && String(item.parent).indexOf("ColumnLayout") >= 0) item.parent.Layout.minimumWidth = 0;
          item.font.pixelSize = 14;
          if (/^[0-9?]+\//.test(item.text)) {
            item.font.pixelSize = 19;
            item.Layout.preferredWidth = 76; item.Layout.maximumWidth = 76;
            item.parent.anchors.rightMargin = 34;
          }
          adaptedControls.push(item);
        } else if (lobbyPage && "text" in item && "display" in item && item.text === Lua.tr("Exit Lobby")) {
          // Material's implicit height includes its vertical style insets.
          // A fixed 40 px control shrinks the visible pill below its siblings.
          item.height = Qt.binding(function() { return item.implicitHeight; });
          item.width = Qt.binding(function() { return Math.max(120,item.implicitWidth); });
          item.font.pixelSize = 16;
          item.anchors.top = item.parent.top; item.anchors.topMargin = 16;
          item.anchors.rightMargin = 8;
          item.icon.width = 20; item.icon.height = 20;
          adaptedControls.push(item);
        } else if (lobbyPage && "textFormat" in item && item.textFormat === Text.MarkdownText) {
          item.font.pixelSize = 14; adaptedControls.push(item);
        } else if ((chatBox || lobbyPage) && "textFont" in item && "clicked" in item) {
          const icons = {"🗨️":"sound", "😃":"emoji", "✔️":"send", "语音":"sound", "表情":"emoji", "发送":"send"};
          const toggle = String(item.text).indexOf("🗨️") === 0 && item.text.length > "🗨️".length;
          if ((icons[item.text] || toggle) && "icon" in item && "title" in item) {
            if (toggle) {
              // Leave the original text binding intact: it tracks chatShown.
              item.icon.source = Qt.binding(function() {
                return host.chatIcon(String(item.text).indexOf("➕") >= 0 ? "expand" : "collapse");
              });
            } else {
              item.icon.source = host.chatIcon(icons[item.text]);
              item.text = "";
            }
            item.icon.width = 24; item.icon.height = 24;
            item.title.visible = false;
            item.width = 40; item.height = 40; adaptedControls.push(item);
          }
        }
      }
      for (const child of children) scan(child,depth+1,serverPage,lobbyPage,chatBox);
      // Native FileDialog objects are in data, not visual children.
      const data = item.data;
      if (data && typeof data === "object" && typeof data.length === "number")
        for (let i=0; i<data.length; i++) scan(data[i],depth+1,serverPage,lobbyPage,chatBox);
    }
    scan(rootItem || window.contentItem,0,false,false,false);
  }
  // No steady-state whole-window timer: large overview pages must remain idle.
  Connections {
    target: host.currentScene
    ignoreUnknownSignals: true
    function onPopupItemChanged() { Qt.callLater(host.adaptRoomPopup); visibleCardCapture.restart(); }
  }
  Timer {id:visibleCardCapture;interval:32;onTriggered:{host.rememberPopupCards();host.rememberInfoCards();}}
  function visibleCardIds(item) {
    const ids=new Set(),pending=[item];
    while(pending.length) {
      const node=pending.pop();
      if(!node || !node.visible)continue;
      if(String(node).indexOf("CardItem_QMLTYPE")===0 && node.dataModel && node.known===true && node.dataModel.cardId>0)
        ids.add(node.dataModel.cardId);
      if(node.children)pending.push(...Array.from(node.children));
    }
    return ids;
  }
  function rememberVisible(ids, evidence) {
    if(!ids.size)return;
    const args=evidence ? evidence.ids.join(',')+'},'+JSON.stringify(evidence.edge)+','+evidence.count : Array.from(ids).join(',')+'}';
    try {Lua.ev('(function() FkCardCounterV2=FkCardCounterV2 or dofile("card-counter/counter.lua"); return FkCardCounterV2.remember({' + args + ') end)()');}
    catch(_) { /* The client may have been replaced while closing. */ }
    Qt.callLater(host.syncKnownHandBadges);
  }
  function deckEvidence(ids, edge, visibleIds) {
    const ordered=Array.from(ids || []);
    const count=Number(currentScene.dataModel && currentScene.dataModel.drawPileNum);
    return ordered.length && ordered.every(id=>visibleIds.has(id)) && Number.isInteger(count) && count>=ordered.length && count<=10000
      ? {ids:ordered,edge:edge,count:count} : null;
  }
  function rememberInfoCards() {
    const item=detailPopup && detailPopup.visible && detailPopup.item;
    if(!item || !item.visible)return;
    const ids=visibleCardIds(item);
    let evidence=null;
    // Eagle Sight exposes its exact prefix through the stock public mark spec.
    // Match the opened view to that spec; unrelated piles imply no deck order.
    for(const player of currentScene.dataModel.players || []) for(const mark of player.marks || []) {
      const spec=mark.qml,shown=spec && spec.prop && spec.prop.ids;
      if(mark.origName!=="@[yingshis]" || !shown || !item.ids ||
         spec.name!=="ViewPile" || spec.uri!=="LunarLtk.Pages.InfoPopups")continue;
      if(JSON.stringify(Array.from(shown))===JSON.stringify(Array.from(item.ids))) evidence=deckEvidence(shown,"top",ids);
    }
    rememberVisible(ids,evidence);
  }
  function popupDeckEvidence(item, visibleIds) {
    const model=item.dataModel;
    if (model && model.poxiType==="guanxu_exchange" && model.cardData) {
      const row=Array.from(model.cardData).find(row=>row[0]==="Top");
      return row ? deckEvidence(row[1],"top",visibleIds) : null;
    }
    if (model && revealFocusSkill==="quanbian" && model.origCards && model.areaNames && model.areaNames[0]==="Top")
      return deckEvidence(model.origCards[0],"top",visibleIds);
    if (!model || model.minNum!==0 || model.maxNum!==0 || !model.cards) return null;
    let ordered=Array.from(model.cards);
    // Only the face-up cards that the actual view dialog exposes are eligible.
    if (!ordered.length || ordered.some(id => !visibleIds.has(id))) return null;
    const prompt=String(model.promptText || ""), raw=String(model.prompt || "");
    let edge="";
    const bottom=/牌堆底|bottom.*(?:draw|deck)|(?:draw|deck).*bottom/i.test(prompt);
    const top=/牌堆顶|top.*(?:draw|deck)|(?:draw|deck).*top/i.test(prompt);
    if (bottom && !top) edge="bottom";
    else if (top && !bottom) edge="top";
    // Xunxiang uses the generic view-cards prompt, but its current request is
    // explicitly focused on that skill. Other generic views have no order.
    else if (raw==="$ViewCards" && /(^|[#_])xunxiang$/.test(revealFocusSkill)) edge="top";
    if ((edge==="bottom" && /左[^，。]*最[^，。]*底/.test(prompt)) ||
        (edge==="top" && /右[^，。]*最[^，。]*顶/.test(prompt))) ordered.reverse();
    const count=Number(currentScene.dataModel && currentScene.dataModel.drawPileNum);
    return edge && Number.isInteger(count) && count>=ordered.length && count<=10000
      ? {ids:ordered,edge:edge,count:count} : null;
  }
  function rememberPopupCards() {
    const item=currentScene && currentScene.popupItem;
    if(!item || !item.visible) return;
    const ids=visibleCardIds(item);
    if(!ids.size)return;
    const evidence=popupDeckEvidence(item,ids);
    // Record the other visible row too: Guanxu also reveals the target's hand.
    if(evidence)rememberVisible(ids,null);
    rememberVisible(ids,evidence);
  }
  function rememberArrangement(item) {
    const model=item && item.dataModel;
    if(!item || !item.visible || !model)return;
    if(revealFocusSkill==="xinghun" && model.areaNames && model.areaNames[0]==="Top" &&
       model.areaNames[1]==="$Hand" && model.origCards && model.result) {
      // These top cards are temporarily in Processing, not in the draw pile.
      // Capture the actually shown faces at confirmation too (including a
      // quick confirmation before the deferred capture), then let visible
      // Processing/hand -> deck moves establish the confirmed top order.
      rememberVisible(visibleCardIds(item),null);
      return;
    }
    if(revealFocusSkill!=="quanbian" || !model.areaNames ||
       model.areaNames[0]!=="Top" || model.areaNames[1]!=="toObtain" || !model.result || !model.origCards)return;
    // Quanbian leaves the arranged prefix and removes the chosen card. Place
    // that outgoing card after the remainder, then the move hook removes it.
    const ids=visibleCardIds(item),original=Array.from(model.origCards[0] || []);
    const ordered=Array.from(model.result[0] || []).concat(Array.from(model.result[1] || []));
    if(ordered.length!==original.length || new Set(ordered).size!==ordered.length || ordered.some(id=>original.indexOf(id)<0))return;
    const evidence=deckEvidence(ordered,"top",ids);
    if(evidence)rememberVisible(ids,evidence);
  }
  function adaptRoomPopup() {
    const item = currentScene && currentScene.popupItem;
    arrangementBoxes=arrangementBoxes.filter(box=>box && box.parent);
    if (item) {
      if(item.dataModel && item.dataModel.origCards && item.dataModel.result &&
         arrangementBoxes.indexOf(item)<0) {
        const capture=arrangementCaptureComponent.createObject(item,{box:item});
        if(capture)arrangementBoxes.push(item);
      }
      refreshCompatibility(item);
    }
  }
  property var fallbackButton: null
  onClientContextChanged: {
    bootstrapReady = false;
    if (clientContext) Qt.callLater(host.syncScene);
    else { Qt.callLater(host.releaseScene); Qt.callLater(host.resetDisconnectedHome); }
  }
  Connections {
    target: Config
    // Do not save while loadConf is assigning defaults and stored values.
    function onRoomBgChanged() { host.backgroundChanged("roomBg"); }
    function onLobbyBgChanged() { host.backgroundChanged("lobbyBg"); }
  }
  function backgroundChanged(key) {
    if (!settingsReady) return;
    const value = String(Config[key]);
    if (Cpp.os === "iOS" && value.startsWith("file:") && value.indexOf("/assets/backgrounds/") < 0 &&
        typeof Backend.importBackground === "function") {
      const local = Backend.importBackground(value);
      if (local) Config[key] = local;
      else console.warn("[ClientUI] background import failed");
    }
    backgroundSave.restart();
  }
  Timer { id: backgroundSave; interval: 250; onTriggered: Config.saveConf(); }
  function releaseScene() {
    for (const badge of knownHandBadges) disposeRoomItem(badge);
    knownHandBadges = []; knownHandCounts = ({}); knownHandPayload = "";
    const oldDeckHit=deckHit, oldFallback=fallbackButton, oldPopup=popup;
    deckHit = null; deckItem = null; fallbackButton = null; popup = null; currentScene = null;
    disposeRoomItem(oldDeckHit); disposeRoomItem(oldFallback); disposeRoomItem(oldPopup);
  }
  function ensureBootstrap() {
    // C++ publishes its process-global ClientInstance before its worker thread
    // finishes constructing the Lua VM. The QML context is set only afterwards.
    // Never call Backend.evalLuaExp through that partially constructed client.
    if (typeof ClientInstance === "undefined" || !ClientInstance) return false;
    if (bootstrapReady) return true;
    try {
      bootstrapReady = Lua.ev('(function() if not ClientInstance or not Client or not Fk then return false end if not FkCardCounterRuntimeReady then dofile("card-counter/bootstrap.lua"); FkCardCounterRuntimeReady=true; if fk and fk.qInfo then fk.qInfo("[CardCounter] client runtime ready") end end return true end)()') === true;
      return bootstrapReady;
    } catch(e) {
      if (String(e)!==lastError) console.warn("[CardCounter] "+e);
      lastError=String(e);return false;
    }
  }
  // Stay outside native notification call stacks: a queued context change and
  // timer install the host only after the native client has finished creation.
  // BEGIN AUTO LUCK CARD: only answer the stock server-issued luck-card request.
  property var luckPanel: null
  Connections {
    target: host
    function onCurrentSceneChanged() {
      const panel=host.luckPanel; host.luckPanel=null;
      try { if (panel && typeof panel.stopAuto === "function") panel.stopAuto("已离开房间"); } catch (_) {}
      host.disposeRoomItem(panel);
    }
  }
  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) { host.handleLuckCommand(command, data); }
  }
  function handleLuckCommand(command, data) {
    if (command === "AskForSkillInvoke" && data && data[0] === "AskForLuckCard") {
      if (!directionalLuckEnabled || !currentScene || !currentScene.dataModel || Config.observing || Config.replaying) return;
      if (!luckPanel) luckPanel = luckCardPanel.createObject(currentScene, {scene:currentScene});
      if (luckPanel) luckPanel.receiveRequest(data);
    } else if (luckPanel) {
      if (command === "ReplyToServer") {
        if (!luckPanel.consumeOwnReply(data)) luckPanel.stopAuto("已转为手动操作");
      } else if (command === "CancelRequest") luckPanel.prepareRequestChange();
      else if (["AskForSkillInvoke","PlayCard","AskForUseCard","AskForResponseCard","AskForUseActiveSkill","AskForChoices","GameOver","BackToStart","EnterLobby","EnterRoom"].indexOf(command)>=0)
        luckPanel.endRequest();
    }
  }
  Component {
    id: luckCardPanel
    Control {
      id: luck
      objectName: "autoLuckCardPanel"
      required property var scene
      readonly property var model: scene && scene.dataModel
      width: parent ? Math.min(440, parent.width-24) : 440
      height: 315
      x: 12; y: 50; z: 1100
      background: Rectangle {radius:9;color:"#f0213439";border.color:"#c6ac73"}
      font.pixelSize: 14
      Material.theme: Material.Dark
      Material.foreground: "#e5ded0"
      Material.background: "#315054"
      Material.accent: "#d9bd83"
      palette.windowText: "#e5ded0"; palette.text: "#e5ded0"
      palette.buttonText: "#e5ded0"; palette.button: "#315054"
      palette.base: "#20383e"; palette.highlight: "#9f8757"; palette.highlightedText: "#fff5dc"
      visible: false
      property bool running: false
      property bool dismissed: false
      property string pendingOwnReply: ""
      property bool waiting: false
      property string requestKey: ""
      property string consumedKey: ""
      property string expectedPrompt: ""
      property var requestMeta: ({})
      property var goals: []
      property int used: 0
      property int remaining: -1
      property string statusText: "选择目标后点击开始"
      function canonical(s) {
        s=String(s || "").trim().toLowerCase();
        return ({"ak":"crossbow","连弩":"crossbow","诸葛连弩":"crossbow","丈八":"spear","丈八蛇矛":"spear","杀":"slash"})[s] || s;
      }
      function parseGoals(text) {
        const parts=String(text).split(/[,，]/);
        if (!parts.length || parts.length>6) return null;
        const out=[];
        for (const part of parts) {
          const m=part.trim().match(/^([^:：×*]+?)(?:[:：×*]\s*(\d+))?$/);
          if (!m) return null;
          const names=m[1].split("/").map(n=>canonical(n));
          const count=m[2]===undefined ? 1 : Number(m[2]);
          if (names.some(n=>!n) || !Number.isInteger(count) || count<1 || count>99) return null;
          out.push({names:names,count:count});
        }
        return out;
      }
      function matches(cards, rules) {
        return rules.length>0 && rules.every(rule=>cards.filter(card=> {
          const base=String(card.trueName || card.name || "").split("__").pop();
          const names=[canonical(base),canonical(card.name),canonical(Lua.tr(card.name))];
          if (base === "slash" || /_slash$/.test(base)) names.push("slash");
          return rule.names.some(n=>names.indexOf(n)>=0);
        }).length>=rule.count);
      }
      function stopAuto(message) {
        action.stop(); watchdog.stop(); running=false; waiting=false; pendingOwnReply="";
        if (message) statusText=message;
      }
      function endRequest() { cancelProbe.stop(); stopAuto("手气卡询问已结束"); requestKey=""; visible=false; dismissed=false; }
      // ClientCallback emits CancelRequest before EVERY AskFor request, including
      // the next luck-card reroll. Wait briefly for its queued replacement.
      function prepareRequestChange() { action.stop(); cancelProbe.restart(); }
      function consumeOwnReply(data) {
        if (pendingOwnReply && String(data)===pendingOwnReply) { pendingOwnReply=""; return true; }
        return false;
      }
      function dismiss() { dismissed=true; stopAuto("已关闭，本轮不再弹出"); visible=false; }
      function currentRequestValid() {
        if (!model || scene!==host.currentScene || !scene.visible || Config.observing || Config.replaying ||
            !luck.Window.window || !luck.Window.window.active || !luck.Window.window.visible || !Lua.selfPlayer ||
            model.dashboardId!==Lua.selfPlayer.id || model.prompt!==expectedPrompt || !requestKey) return false;
        const meta=Backend.getRequestData();
        return String(meta.id)+"|"+String(meta.timestamp)+"|"+expectedPrompt===requestKey &&
          Number(meta.timeout)>0 && Date.now()<Number(meta.timestamp)+Number(meta.timeout)*1000;
      }
      function receiveRequest(data) {
        const meta=Backend.getRequestData();
        const prompt=String(data[1] || "");
        const key=String(meta.id)+"|"+String(meta.timestamp)+"|"+prompt;
        cancelProbe.stop();
        if (key===requestKey) return;
        watchdog.stop(); waiting=false; pendingOwnReply=""; requestMeta=meta;
        requestKey=key; expectedPrompt=prompt;
        const m=prompt.match(/^#AskForLuckCard:::(\d+)$/);
        remaining=m ? Number(m[1]) : -1;
        visible=!dismissed;
        if (running && !dismissed) action.restart();
      }
      function startAuto() {
        if (dismissed) return;
        goals=parseGoals(goalInput.text);
        if (!goals) {statusText="目标格式：连弩，杀:2；斜线表示任选一种";return;}
        if (!currentRequestValid() || !model.okEnabled || !model.cancelEnabled) {
          statusText="当前没有可操作的手气卡询问"; return;
        }
        used=0; running=true; waiting=false; statusText="正在检查当前手牌"; action.restart();
      }
      function act() {
        if (!running || waiting || dismissed) return;
        if (!currentRequestValid() || !model.okEnabled || !model.cancelEnabled) {
          stopAuto("询问或操作状态已变化，自动刷牌停止"); return;
        }
        if (requestKey===consumedKey) {stopAuto("本次手气卡已处理");return;}
        const cards=Array.from(model.dashboard && model.dashboard.handcards || []);
        if (!cards.length || cards.some(c=>!c || !c.known || !(c.cardId>0))) {
          stopAuto("手牌尚未同步，已暂停；请重试或手动操作");return;
        }
        const hit=matches(cards,goals);
        if (!hit && remaining===0) {stopAuto("服务器手气卡次数已用完");return;}
        consumedKey=requestKey; pendingOwnReply=hit ? "__cancel" : "1"; waiting=!hit;
        if (hit) {running=false;statusText="已满足目标，保留当前手牌";}
        else {used++;statusText="已换牌 "+used+" 次，等待服务器发牌";watchdog.restart();}
        try { Lua.updateRequestUI("Button", hit ? "Cancel" : "OK"); }
        catch (_) {stopAuto("操作未完成，已停止，请手动确认");}
      }
      Timer {id:action;interval:300;onTriggered:luck.act()}
      Timer {id:cancelProbe;interval:100;onTriggered:luck.endRequest()}
      Timer {id:watchdog;interval:8000;onTriggered:luck.stopAuto("服务器未继续手气卡询问，已停止")}
      Connections {
        target: luck.Window.window
        function onActiveChanged() { if (!luck.Window.window.active) luck.stopAuto("已暂停，可返回后手动开始"); }
        function onVisibleChanged() { if (!luck.Window.window.visible) luck.stopAuto("已暂停，可返回后手动开始"); }
      }
      Connections {
        target: luck.scene
        function onVisibleChanged() { if (!luck.scene.visible) luck.endRequest(); }
      }
      Connections {
        target: Config
        ignoreUnknownSignals: true
        function onObservingChanged() { if (Config.observing) luck.endRequest(); }
        function onReplayingChanged() { if (Config.replaying) luck.endRequest(); }
      }
      ColumnLayout {
        anchors.fill: parent; anchors.margins: 12; spacing: 6
        RowLayout {
          Layout.fillWidth: true
          Label {text:"自动手气卡";color:"#f3dfb0";font.pixelSize:18;Layout.fillWidth:true}
          Button {objectName:"autoLuckClose";text:"关闭";flat:true;Layout.preferredWidth:52;Layout.preferredHeight:36;leftPadding:2;rightPadding:2;topInset:0;bottomInset:0;font.pixelSize:13;onClicked:luck.dismiss()}
        }
        ComboBox {
          objectName:"autoLuckPresets";Layout.fillWidth:true;enabled:!luck.running
          model:["连弩或丈八","连弩＋至少一张杀","连弩＋至少两张杀","丈八＋至少两张杀","自定义目标"]
          onActivated: {
            const presets=["诸葛连弩/丈八蛇矛","诸葛连弩，杀:1","诸葛连弩，杀:2","丈八蛇矛，杀:2"];
            if (currentIndex<presets.length) goalInput.text=presets[currentIndex];
          }
        }
        TextField {
          id:goalInput;objectName:"autoLuckGoals";Layout.fillWidth:true;enabled:!luck.running
          text:"诸葛连弩/丈八蛇矛";placeholderText:"例：连弩，杀:2";font.pixelSize:15;maximumLength:160
        }
        Label {Layout.fillWidth:true;text:"逗号表示同时满足，/ 表示任选；牌名:张数";color:"#d6d2bd";font.pixelSize:12;wrapMode:Text.Wrap}
        RowLayout {
          Button {objectName:"autoLuckStart";text:"开始自动刷牌";enabled:!luck.running;Layout.fillWidth:true;onClicked:luck.startAuto()}
          Button {objectName:"autoLuckStop";text:"停止";enabled:luck.running;onClicked:luck.stopAuto("已停止，可手动选择")}
        }
        Label {objectName:"autoLuckStatus";Layout.fillWidth:true;text:luck.statusText;color:"#efd49c";font.pixelSize:13;wrapMode:Text.Wrap}
        Label {Layout.fillWidth:true;text:luck.remaining>=0 ? "服务器剩余次数："+luck.remaining : "换牌次数和倒计时以服务器为准";color:"#bdc8c6";font.pixelSize:12}
      }
    }
  }
  // END AUTO LUCK CARD
  function findDeck(item) {
    if (!item) return null;
    if (item.source !== undefined && String(item.source).indexOf("card-back")>=0 && Math.abs(item.width-32)<1 && Math.abs(item.height-42)<1) return item;
    for (const child of item.children || []) {
      const found=findDeck(child);
      if (found) return found;
    }
    return null;
  }
  Component {
    id: hitComponent
    MouseArea {
      objectName:"counterDeckHit"
      property var counter
      anchors.centerIn:parent
      width:Math.max(44,parent.width);height:Math.max(48,parent.height)
      z:9;cursorShape:Qt.PointingHandCursor
      onClicked:counter.toggle()
    }
  }
  Component {
    id: fallbackComponent
    Rectangle {
      objectName: "counterFallbackButton"
      property var counter
      width: 88; height: 40; radius: 7; z: 50
      anchors.right: parent.right; anchors.rightMargin: 72
      anchors.top: parent.top; anchors.topMargin: 8
      color: "#dc243b40"; border.color: "#d9bd83"
      Text { anchors.centerIn: parent; text: "记牌器"; color: "#fff0d2"; font.pixelSize: 16 }
      MouseArea { anchors.fill: parent; onClicked: counter.toggle() }
    }
  }
  function syncScene() {
      // Backend uses the current Lua VM; a new login gets a fresh host module.
      if (!host.ensureBootstrap()) return;
      const scene=host.activeRoomScene;
      if (!scene || !scene.dataModel) { if (host.currentScene) host.releaseScene(); return; }
      if (scene!==host.currentScene) {
        host.releaseScene();
        const component=Qt.createComponent("CardCounter.qml");
        if (component.status!==Component.Ready) {console.warn("[CardCounter] "+component.errorString());return;}
        host.popup=component.createObject(scene,{roomModel:scene.dataModel});
        if (!host.popup) return;
        host.currentScene=scene;
        host.fallbackButton=fallbackComponent.createObject(scene,{counter:host.popup});
        host.deckItem=null;host.deckHit=null;host.deckSearchTicks=0;
        host.refreshCompatibility(scene); // Adapt once when a new table is created.
        host.syncKnownHandBadges();
        console.log("[CardCounter] standalone UI attached");
      }
      host.linkDeck();
      host.adaptRoomPopup();
  }
  function linkDeck() {
      if (!host.deckHit && host.currentScene) {
        const item=host.findDeck(host.currentScene);
        if (item) {
          if (host.fallbackButton) host.fallbackButton.visible=false;
          host.deckItem=item;host.deckHit=hitComponent.createObject(item,{counter:host.popup});
          console.log("[CardCounter] original deck icon linked");
        }
      }
      }
  Timer {
    // Retry only while the newly-created client is not ready. The steady-state
    // room no longer needs a 500 ms scene-discovery callback.
    interval:500;repeat:true;running:host.clientContext!==null && !host.bootstrapReady
    onTriggered:host.syncScene()
  }
  Timer {
    interval:500;repeat:true
    running:host.clientContext!==null && host.currentScene!==null && !host.deckHit && host.deckSearchTicks<3
    onTriggered:{host.deckSearchTicks++;host.linkDeck();}
  }
  // The tracker is updated by the stock move callbacks, so this timer only
  // refreshes the small badge set while a room is actually on screen.
  Timer {
    interval: 500
    repeat: true
    running: host.currentScene !== null && !!host.Window.window && host.Window.window.visible
    onTriggered: host.syncKnownHandBadges()
  }
}
