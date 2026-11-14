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
  onCurrentSceneChanged: { cancelPresentQueue(); revealFocusSkill=""; Qt.callLater(host.adaptPlayerDetail); }
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
    function onVisibleChanged() { if (!host.currentScene.visible) {host.cancelPresentQueue();} }
  }
  Connections {
    target: host.Window.window
    function onActiveChanged() { if (!host.Window.window.active) {host.cancelPresentQueue();} }
  }
  Connections {
    target: Config
    ignoreUnknownSignals: true
    function onReplayingChanged() { if (Config.replaying) {host.cancelPresentQueue();} }
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
  onNavigationRootChanged: requestCompatibility()
  onNavigationPageChanged: requestCompatibility()
  Connections {
    target: host.navigationStack
    ignoreUnknownSignals: true
    function onBusyChanged() { if (!host.navigationStack.busy) host.requestCompatibility(); }
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
  property var photoLocations: []
  property bool hideTitles: false
  property bool preferencesLoaded: false
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
      preferencesLoaded = true;
      requestCompatibility();
    } catch (_) { console.warn("[ClientUI] preferences unreadable; preserving file"); }
  }
  function setHideTitles(value) {
    const payload = JSON.stringify({hideTitles: !!value});
    if (!preferencesLoaded || !Backend.writeFileToAssets("client-ui.json", payload)) return false;
    hideTitles = !!value; refreshCompatibility(); return true;
  }
  Component {
    id: knownHandBadgeComponent
    Rectangle {
      objectName: "knownHandBadge"
      required property var photo
      property int knownCount: 0
      width: Math.max(52, badgeText.implicitWidth + 16)
      height: 22
      radius: 11
      z: 10000
      color: "#D4232D2F"
      border.width: 1
      border.color: "#D5B471"
      visible: knownCount > 0 && photo && photo.visible
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.bottom
      anchors.topMargin: -3
      Text {
        id: badgeText
        anchors.centerIn: parent
        text: "明牌 " + parent.knownCount
        color: "#F8E7B6"
        font.pixelSize: 12
        font.bold: true
      }
    }
  }
  function knownHandKey(model) {
    if (!model) return "";
    const id = model.playerid !== undefined ? model.playerid : model.id;
    return id === undefined || id === null ? "" : String(id);
  }
  function readKnownHandCounts() {
    if (typeof ClientInstance === "undefined" || !ClientInstance) return {};
    try {
      const value = Lua.ev('(function() if not FkCardCounterV2 then FkCardCounterV2 = dofile("card-counter/counter.lua") end return FkCardCounterV2.current("slash") end)()');
      const counts = ({}), rows = value && value.knowledge && value.knowledge.hands || [];
      for (const row of rows) {
        if (!row || row.uncertain === true) continue;
        const key = row.ownerId === undefined || row.ownerId === null ? "" : String(row.ownerId);
        if (key) counts[key] = (counts[key] || 0) + 1;
      }
      return counts;
    } catch (_) { return {}; }
  }
  function syncKnownHandBadges() {
    const scene = currentScene;
    const players = scene && scene.dataModel && scene.dataModel.players || [];
    const counts = readKnownHandCounts();
    const payload = JSON.stringify(counts);
    knownHandPayload = payload;
    knownHandCounts = counts;
    knownHandBadges = knownHandBadges.filter(b => b && b.photo && b.parent);
    for (const model of Array.from(players)) {
      const photo = model && model.photoItem;
      if (!photo) continue;
      let badge = knownHandBadges.find(b => b.photo === photo);
      if (!badge) {
        badge = knownHandBadgeComponent.createObject(photo, {photo: photo});
        if (badge) knownHandBadges.push(badge);
      }
      if (badge) badge.knownCount = counts[knownHandKey(model)] || 0;
    }
    triggerGuanNingSkinEffects(players);
  }
  function triggerGuanNingSkinEffects(players) {
    const states = guanNingSkinStates.filter(s => s && s.photo && s.photo.parent);
    const active = [];
    for (const model of Array.from(players || [])) {
      const photo = model && model.photoItem;
      if (!photo) continue;
      const general = String(photo.general || model.general || "");
      // Only Guan Ning is in scope; Gan Ning is a different general.
      if (!/^(guanning|guan_ning|guan-ning|管宁)$/i.test(general)) continue;
      const source = photo.skinSource;
      const skin = source && (source.name || source.skinName || "");
      if (!skin) continue;
      const signature = general + ":" + String(skin);
      const old = states.find(s => s.photo === photo);
      if (old && old.signature === signature) { active.push(old); continue; }
      let areas = [];
      const pending = [photo], seen = new Set();
      while (pending.length) {
        const item = pending.pop();
        if (!item || seen.has(item)) continue;
        seen.add(item);
        if ("skelData" in item && item.skelData) {
          const nodes = [], nested = [item];
          for (let ni = 0; ni < nested.length; ni++) {
            const child = nested[ni];
            if (!child) continue;
            if (typeof child.setAnimation === "function") nodes.push(child);
            if (child.children) nested.push(...Array.from(child.children));
            if (child.item) nested.push(child.item);
          }
          areas.push({data:item.skelData, nodes:nodes});
        }
        if (item.children) pending.push(...Array.from(item.children));
        if (item.item) pending.push(item.item);
      }
      let triggered = false;
      for (const area of areas) {
        const data = area.data, nodes = area.nodes;
        for (let i = 0; i < nodes.length; i++) {
          const animation = i === 0 && data.bgShownAnim ? data.bgShownAnim : data.bodyShownAnim;
          if (!animation) continue;
          try {
            nodes[i].setAnimation(0, animation, false);
            const normal = i === 0 ? data.bgNormalAnim : data.bodyNormalAnim;
            if (normal) nodes[i].addAnimation(0, normal, true);
            triggered = true;
          } catch (_) { /* a skin may unload between discovery and replay */ }
        }
      }
      // Wait for the loader to expose the Spine nodes before remembering the
      // signature; the next room tick will then replay the effect after load.
      if (!areas.some(area => area.nodes.length)) continue;
      active.push({photo: photo, signature: signature});
      if (triggered) console.log("[CardCounter] replayed Guan Ning skin entrance effect");
    }
    guanNingSkinStates = active;
  }
  function chatIcon(kind) {
    const shapes = {
      sound: '<path d="M3 4h18v13H11l-5 4v-4H3z" fill="white" stroke="#161616" stroke-width="1.3"/>',
      emoji: '<circle cx="12" cy="12" r="10" fill="#ffd348" stroke="#ba8822"/><ellipse cx="8.5" cy="9" rx="1.4" ry="2" fill="#35271b"/><ellipse cx="15.5" cy="9" rx="1.4" ry="2" fill="#35271b"/><path d="M6.5 14h11c-1 6-10 6-11 0" fill="#513824"/><path d="M8 14h8v2H8z" fill="white"/>',
      send: '<path d="M4 12l5 6L21 4" fill="none" stroke="#91a9bc" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
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
    const room = currentScene && currentScene.dataModel;
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
      if (!currentScene || currentScene!==presentQueueScene || Config.replaying || !clientContext ||
          !currentScene.visible || (host.Window.window && !host.Window.window.active)) { cancelPresentQueue(); return; }
      const valid=actionTargets().map(p=>p.playerid);
      const pending=presentQueue.slice(); const id=pending.shift(); presentQueue=pending;
      if (valid.indexOf(id)>=0) clientContext.notifyServer("Chat",{type:2,msg:"$@"+presentQueueKind+":"+id});
    }
    presentQueueScene=null;
  }
  function sendPresent(kind) {
    if (presentRestSeconds > 0 || presentQueue.length || !currentScene || Config.replaying || !clientContext ||
        ["Egg","Flower"].indexOf(kind)<0) return false;
    const selfId = typeof Self !== "undefined" && Self ? Self.id : 0;
    const ids = [];
    for (const p of actionTargets()) {
      const id=p.playerid;
      if (Number.isInteger(id) && id !== 0 && id !== -1 && ids.indexOf(id)<0 &&
          (kind !== "Egg" || id !== selfId)) ids.push(id);
    }
    if (!ids.length) return false;
    presentQueue=ids; presentQueueScene=currentScene; presentQueueKind=kind;
    presentRestSeconds=10; presentRest.restart();
    sendNextPresent(); return true;
  }
  Timer {id:presentRest;interval:1000;repeat:true;onTriggered:{
    host.presentRestSeconds--; if (host.presentRestSeconds <= 0) stop();
  }}
  component PresentButton: Button {
    property string presentKind
    width: implicitWidth; height: 40
    font.pixelSize: 16
    leftPadding: 8; rightPadding: 8; topInset: 0; bottomInset: 0
    enabled: !!host.currentScene && host.currentScene.visible && !Config.replaying && !!host.clientContext &&
      host.presentRestSeconds === 0 && !host.presentQueue.length
    autoRepeat: false
    background: Rectangle {radius:6;color:parent.down ? "#5C3D3D" : "#2A1F1F";border.color:"#6B4F3A";opacity:parent.enabled ? 1 : 0.35}
    contentItem: Text {text:parent.text;font:parent.font;color:"#E8D5B0";horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}
    ToolTip.visible: hovered || down
    ToolTip.text: host.presentRestSeconds>0 ? "冷却中："+host.presentRestSeconds+" 秒" :
      host.presentQueue.length ? "正在同批发送" :
      "点按向全员同批发送，砸蛋排除自己；共用 10 秒冷却"
    onClicked: host.sendPresent(presentKind)
  }
  function refreshCompatibility(rootItem) {
    // Never walk the entire animated table from a periodic UI-thread callback.
    // Android room popups are adapted through popupItemChanged, in isolation.
    if (Cpp.os === "Android" && activeRoomScene && !rootItem) return;
    const window = host.Window.window;
    if (!window) return;
    // Cache surviving controls so bindings are installed once per instance.
    titleBadges = titleBadges.filter(x => x && x.parent);
    adaptedControls = adaptedControls.filter(x => x && x.parent);
    const ios = Cpp.os === "iOS";
    let visited = 0;
    const seen = new Set();
    function scan(item, depth, serverPage, lobbyPage, chatBox) {
      if (!item || (typeof item !== "object" && typeof item !== "function") || seen.has(item) || depth > 24 || ++visited > 12000) return;
      seen.add(item);
      if ("model" in item) host.prepareSkinMenu(item.model);
      const type = String(item);
      if (type.indexOf("SwipeView_QMLTYPE") === 0) host.adaptRoomDrawerSwipe(item);
      if (type.indexOf("PlayerDetail_QMLTYPE") === 0) host.adaptPlayerDetail(item);
      if (type.indexOf("AvatarChatBox_QMLTYPE") === 0 && typeof item.loadSkills === "function")
        host.attachRoleVoices(item);
      if ((Cpp.os==="Android" || Cpp.os==="iOS") &&
          (type.indexOf("LogEdit_QMLTYPE")===0 || type.indexOf("RoomGameLogEdit_QMLTYPE")===0))
        host.adaptTouchLog(item);
      serverPage = serverPage || ("selectedServer" in item && "serverListUrl" in item);
      lobbyPage = lobbyPage || ("roomModel" in item && "serverPlayerNum" in item);
      chatBox = chatBox || type.indexOf("ChatBox_QMLTYPE") === 0;
      // Do not traverse the overview's dense delegate trees during navigation.
      if (!serverPage && !lobbyPage && "cellWidth" in item && "cellHeight" in item && "delegate" in item && "model" in item) return;
      if (serverPage && adaptedControls.indexOf(item) < 0 && "model" in item && "countChanged" in item && "contentItem" in item) {
        item.countChanged.connect(host.requestCompatibility);
        adaptedControls.push(item);
      }
      const children = item.children || [];
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
            // Android's system document picker cannot browse the app's private
            // recording directory. Use the in-app picker for this entry.
            if (Cpp.os === "Android") item.options |= FileDialog.DontUseNativeDialog;
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
        if (serverPage && "text" in item && "elide" in item && "font" in item) {
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
          item.height = 40; item.font.pixelSize = 14;
          item.icon.width = 20; item.icon.height = 20;
          adaptedControls.push(item);
        } else if (lobbyPage && "textFormat" in item && item.textFormat === Text.MarkdownText) {
          item.font.pixelSize = 14; adaptedControls.push(item);
        } else if (chatBox && "textFont" in item && "clicked" in item) {
          const icons = {"🗨️":"sound", "😃":"emoji", "✔️":"send", "语音":"sound", "表情":"emoji", "发送":"send"};
          if (icons[item.text] && "icon" in item && "title" in item) {
            item.icon.source = host.chatIcon(icons[item.text]);
            item.icon.width = 24; item.icon.height = 24;
            item.text = ""; item.title.visible = false;
            item.width = 40; item.height = 40; adaptedControls.push(item);
          }
        }
      }
      for (const child of children) scan(child,depth+1,serverPage,lobbyPage,chatBox);
      // Native FileDialog objects are in data, not visual children.
      // Some server pages use a scalar/model property named data. Only walk
      // Qt object lists; treating those scalars as iterables throws every tick.
      const declared = item.data;
      if (declared && typeof declared !== "string" && typeof declared.length === "number") {
        for (let i=0; i<declared.length; i++) scan(declared[i],depth+1,serverPage,lobbyPage,chatBox);
      }
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
  onClientContextChanged: { bootstrapReady = false; if (clientContext) Qt.callLater(host.syncScene); else Qt.callLater(host.releaseScene); }
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
    if (deckHit) deckHit.destroy();
    if (fallbackButton) fallbackButton.destroy();
    if (popup) popup.destroy();
    deckHit = null; deckItem = null; fallbackButton = null; popup = null; currentScene = null;
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
      if (host.luckPanel) { host.luckPanel.stopAuto("已离开房间"); host.luckPanel.destroy(); host.luckPanel=null; }
    }
  }
  Connections {
    target: Mediator
    function onCommandGot(sender, command, data) { host.handleLuckCommand(command, data); }
  }
  function handleLuckCommand(command, data) {
    if (command === "AskForSkillInvoke" && data && data[0] === "AskForLuckCard") {
      if (!currentScene || !currentScene.dataModel || Config.observing || Config.replaying) return;
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
