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
  readonly property var activeRoomScene: Ltk.roomScene || null
  onActiveRoomSceneChanged: Qt.callLater(host.syncScene)
  property var popup: null
  property var deckHit: null
  property var deckItem: null
  property string lastError: ""
  property var clientContext: typeof ClientInstance !== "undefined" ? ClientInstance : null
  property bool bootstrapReady: false
  property bool settingsReady: false
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
    if (adaptedControls.indexOf(view)>=0) return;
    adaptedControls.push(view);
    // LogEdit follows the last selected index, rather than the viewport. A
    // manual drag must leave that index before the next live log is appended.
    view.movementStarted.connect(function() { view.currentIndex=-1; });
    view.movementEnded.connect(function() {
      if (view.atYEnd && view.count>0) view.currentIndex=view.count-1;
    });
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
    const control = component.createObject(input, {chatBox:chat, soundList:sound});
    if (control) adaptedControls.push(chat);
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
      const type = String(item);
      if (type.indexOf("AvatarChatBox_QMLTYPE") === 0 && typeof item.loadSkills === "function")
        host.attachRoleVoices(item);
      if ((Cpp.os==="Android" || Cpp.os==="iOS") && type.indexOf("LogEdit_QMLTYPE")===0)
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
    function onPopupItemChanged() { Qt.callLater(host.adaptRoomPopup); }
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
