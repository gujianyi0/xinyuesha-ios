// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
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
  onCurrentSceneChanged: { cancelPresentQueue(); revealFocusSkill=""; playerActions.close(); syncPlayerActions(); }
  property var playerActionWatchers: []
  readonly property var actionRoomModel: currentScene && currentScene.dataModel &&
    ("playersChanged" in currentScene.dataModel || "playerAdded" in currentScene.dataModel) ? currentScene.dataModel : null
  Connections {
    target: host.actionRoomModel
    ignoreUnknownSignals: true
    function onPlayersChanged() { host.syncPlayerActions(); }
    function onPlayerAdded() { host.syncPlayerActions(); }
  }
  Connections {
    target: host.currentScene
    ignoreUnknownSignals: true
    function onVisibleChanged() { if (!host.currentScene.visible) {host.cancelPresentQueue();playerActions.close();} }
  }
  Connections {
    target: host.Window.window
    function onActiveChanged() { if (!host.Window.window.active) {host.cancelPresentQueue();playerActions.close();} }
  }
  Connections {
    target: Config
    ignoreUnknownSignals: true
    function onReplayingChanged() { if (Config.replaying) {host.cancelPresentQueue();playerActions.close();} }
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
      interactionEntry.createObject(input);
      adaptedControls.push(chat);
    }
  }
  Component {
    id: interactionEntry
    Button {
      objectName: "playerInteractionButton"
      text: "互动"; font.pixelSize: 14; leftPadding: 4; rightPadding: 4
      Layout.preferredWidth: 56; Layout.preferredHeight: 44
      visible: !Config.replaying
      ToolTip.visible: hovered
      ToolTip.text: "点按向全员送花或砸蛋，砸蛋排除自己"
      onClicked: host.showPlayerActions(null)
    }
  }
  function actionTargets() {
    const room = currentScene && currentScene.dataModel;
    return Array.from(room && room.players || []).filter(model => model &&
      Number.isInteger(model.playerid) && model.playerid !== 0 && model.playerid !== -1);
  }
  function syncPlayerActions() {
    const models = actionTargets();
    playerActionWatchers = playerActionWatchers.filter(watcher => {
      if (watcher && watcher.scene === currentScene && models.indexOf(watcher.playerModel) >= 0) return true;
      if (watcher) watcher.destroy();
      return false;
    });
    for (const model of models) {
      if (model.photoItem) attachPlayerActions(model.photoItem);
      if (!("photoItemChanged" in model) || playerActionWatchers.some(w => w.playerModel === model)) continue;
      const watcher = playerActionWatcher.createObject(host, {playerModel:model, scene:currentScene});
      if (watcher) playerActionWatchers.push(watcher);
    }
    if (playerActions.visible && models.indexOf(playerActions.targetModel) < 0) playerActions.close();
  }
  Component {
    id: playerActionWatcher
    Connections {
      objectName: "playerActionWatcher"
      required property var playerModel
      required property var scene
      target: playerModel
      function onPhotoItemChanged() {
        if (scene === host.currentScene && playerModel.photoItem) host.attachPlayerActions(playerModel.photoItem);
      }
    }
  }
  function attachPlayerActions(photo) {
    if (!photo || !("rightClicked" in photo) || !("dataModel" in photo)) return;
    if (adaptedControls.indexOf(photo)>=0) return;
    photo.rightClicked.connect(function() {
      Qt.callLater(function() { if(photo && photo.parent) host.showPlayerActions(photo.dataModel); });
    });
    adaptedControls.push(photo);
  }
  function showPlayerActions(model) {
    if (!currentScene || Config.replaying) return;
    let targets = actionTargets();
    if (model && targets.indexOf(model) < 0) targets.push(model);
    if (!model) model = targets.find(p => p.playerid !== (typeof Self !== "undefined" && Self ? Self.id : 0)) || targets[0];
    if (!model || !Number.isInteger(model.playerid) || model.playerid===0 || model.playerid===-1) return;
    if(typeof currentScene.closeInfoPopup==="function")currentScene.closeInfoPopup();
    playerActions.close();
    playerActions.targets=targets;
    playerActions.targetModel=model;
    playerActions.open();
  }
  property var presentQueue: []
  property var presentQueueScene: null
  property string presentQueueKind: ""
  property int presentRestSeconds: 0
  function cancelPresentQueue() {
    if (presentQueue.length) { presentRestSeconds=10; presentRest.restart(); }
    presentSendTimer.stop(); presentQueue=[]; presentQueueScene=null;
  }
  function sendNextPresent() {
    if (!currentScene || currentScene !== presentQueueScene || Config.replaying || !clientContext ||
        !currentScene.visible || (host.Window.window && !host.Window.window.active)) { cancelPresentQueue(); return; }
    const valid = actionTargets().map(p => p.playerid);
    const queue = presentQueue.slice();
    let id = null;
    while (queue.length) { const next = queue.shift(); if (valid.indexOf(next) >= 0) { id=next; break; } }
    presentQueue=queue;
    if (id !== null) clientContext.notifyServer("Chat",{type:2,msg:"$@"+presentQueueKind+":"+id});
    if (!queue.length) { cancelPresentQueue(); presentRestSeconds=10; presentRest.restart(); }
    else presentSendTimer.restart();
  }
  function sendPresent(kind, keepOpen) {
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
    sendNextPresent(); return true;
  }
  // Preserve the server's per-message rate limit rather than flooding all ids
  // in one frame. Only a finite click snapshot is sent; room changes cancel it.
  Timer {id:presentSendTimer;interval:1600;onTriggered:host.sendNextPresent()}
  Timer {id:presentRest;interval:1000;repeat:true;onTriggered:{
    host.presentRestSeconds--; if (host.presentRestSeconds <= 0) stop();
  }}
  Dialog {
    id:playerActions;objectName:"playerPresentActions"
    property var targetModel:null
    property var targets:[]
    parent:Overlay.overlay;anchors.centerIn:parent
    width:Math.min(280,parent ? parent.width-16 : 280)
    height:Math.min(implicitHeight,parent ? parent.height-16 : implicitHeight)
    padding:12; spacing:6
    modal:true;title:"武将互动";exit:Transition {}
    header:Label {text:playerActions.title;font.pixelSize:16;font.bold:true;leftPadding:12;topPadding:10;bottomPadding:4}
    onClosed: {targetModel=null;targets=[];}
    contentItem:ColumnLayout {
      spacing:6
      ComboBox {
        objectName: "presentTargetSelector"
        Layout.fillWidth:true;Layout.preferredHeight:40;font.pixelSize:14
        model: playerActions.targets.map(p => p.screenName || (p.seatNumber ? "第 " + p.seatNumber + " 位玩家" : "玩家"))
        currentIndex: playerActions.targets.indexOf(playerActions.targetModel)
        onActivated: playerActions.targetModel=playerActions.targets[currentIndex]
      }
      Label {
        objectName:"presentCooldownHint";Layout.fillWidth:true;wrapMode:Text.Wrap;font.pixelSize:12
        text:host.presentRestSeconds > 0 ? "冷却中："+host.presentRestSeconds+" 秒，送花／砸蛋共用冷却"
          : host.presentQueue.length ? "正在依次发送，剩余 "+host.presentQueue.length+" 人"
          : "点按向全员发送，砸蛋排除自己\n发送完成后冷却 10 秒"
      }
      RowLayout {
        spacing:8
        PresentButton {objectName:"presentEggButton";text:"全员砸蛋";presentKind:"Egg"}
        PresentButton {objectName:"presentFlowerButton";text:"全员送花";presentKind:"Flower"}
      }
      RowLayout {
        spacing:8
        Button {text:"查看资料";Layout.fillWidth:true;Layout.preferredHeight:38;font.pixelSize:13;onClicked:{
          const model=playerActions.targetModel;playerActions.close();
          if(host.currentScene && model)host.currentScene.showInfoPopup(Qt.createComponent("LunarLtk.Pages.InfoPopups","PlayerDetail"),{dataModel:model});
        }}
        Button {text:"关闭";Layout.fillWidth:true;Layout.preferredHeight:38;font.pixelSize:13;onClicked:playerActions.close()}
      }
    }
  }
  component PresentButton: Button {
    property string presentKind
    Layout.fillWidth:true;Layout.preferredHeight:44;font.pixelSize:14
    enabled: playerActions.opened && !!host.currentScene && !Config.replaying && !!host.clientContext &&
      host.presentRestSeconds === 0 && !host.presentQueue.length
    autoRepeat: false
    onClicked: host.sendPresent(presentKind,true)
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
      if (!item || seen.has(item) || depth > 24 || ++visited > 12000) return;
      seen.add(item);
      if ("model" in item) host.prepareSkinMenu(item.model);
      const type = String(item);
      if ("rightClicked" in item && "dataModel" in item && "playerid" in item && "general" in item && "goBackAnim" in item)
        host.attachPlayerActions(item);
      if (type.indexOf("AvatarChatBox_QMLTYPE") === 0 && typeof item.loadSkills === "function")
        host.attachRoleVoices(item);
      if ((Cpp.os==="Android" || Cpp.os==="iOS") &&
          (type.indexOf("LogEdit_QMLTYPE")===0 || type.indexOf("RoomGameLogEdit_QMLTYPE")===0))
        host.adaptTouchLog(item);
      serverPage = serverPage || ("selectedServer" in item && "serverListUrl" in item);
      lobbyPage = lobbyPage || ("roomModel" in item && "serverPlayerNum" in item);
      chatBox = chatBox || type.indexOf("ChatBox_QMLTYPE") === 0;
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
  Timer {id:visibleCardCapture;interval:32;onTriggered:host.rememberPopupCards()}
  function popupDeckEvidence(item, visibleIds) {
    const model=item.dataModel;
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
    const ids=new Set(),pending=[item];
    while(pending.length) {
      const node=pending.pop();
      if(!node || !node.visible)continue;
      if(String(node).indexOf("CardItem_QMLTYPE")===0 && node.dataModel && node.known===true && node.dataModel.cardId>0)
        ids.add(node.dataModel.cardId);
      if(node.children)pending.push(...Array.from(node.children));
    }
    if(!ids.size)return;
    const evidence=popupDeckEvidence(item,ids);
    const args=evidence ? evidence.ids.join(',')+'},'+JSON.stringify(evidence.edge)+','+evidence.count : Array.from(ids).join(',')+'}';
    try {Lua.ev('(function() FkCardCounterV2=FkCardCounterV2 or dofile("card-counter/counter.lua"); return FkCardCounterV2.remember({' + args + ') end)()');}
    catch(_) { /* The transient client may have been replaced while closing. */ }
  }
  function adaptRoomPopup() {
    const item = currentScene && currentScene.popupItem;
    if (item) refreshCompatibility(item);
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
    playerActions.close(); playerActions.targetModel=null;
    for (const watcher of playerActionWatchers) if (watcher) watcher.destroy();
    playerActionWatchers=[];
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
}
