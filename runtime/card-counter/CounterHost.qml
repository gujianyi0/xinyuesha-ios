// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import Fk
import LunarLtk
Item {
  id: host
  objectName: "fkCounterHost"
  property var currentScene: null
  property var popup: null
  property var deckHit: null
  property var deckItem: null
  property string lastError: ""
  property var clientContext: typeof ClientInstance !== "undefined" ? ClientInstance : null
  property bool bootstrapReady: false
  property bool settingsReady: false
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
    } catch (_) { console.warn("[ClientUI] preferences unreadable; preserving file"); }
  }
  function setHideTitles(value) {
    const payload = JSON.stringify({hideTitles: !!value});
    if (!preferencesLoaded || !Backend.writeFileToAssets("client-ui.json", payload)) return false;
    hideTitles = !!value; refreshCompatibility(); return true;
  }
  function refreshCompatibility() {
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
              const pictures = StandardPaths.standardLocations(StandardPaths.PicturesLocation);
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
        if (serverPage && "text" in item && "elide" in item && "font" in item) {
          item.elide = Text.ElideRight; item.maximumLineCount = 1;
          item.font.pixelSize = 14;
          if (/^[0-9?]+\//.test(item.text)) {
            item.font.pixelSize = 19;
            item.Layout.preferredWidth = 76; item.Layout.maximumWidth = 76;
          }
          adaptedControls.push(item);
        } else if (lobbyPage && "text" in item && "display" in item && item.text === Lua.tr("Exit Lobby")) {
          item.height = 40; item.font.pixelSize = 14;
          item.icon.width = 20; item.icon.height = 20;
          adaptedControls.push(item);
        } else if (lobbyPage && "textFormat" in item && item.textFormat === Text.MarkdownText) {
          item.font.pixelSize = 14; adaptedControls.push(item);
        } else if (chatBox && "textFont" in item && "clicked" in item) {
          const labels = {"🗨️":"语音", "😃":"表情", "✔️":"发送"};
          if (labels[item.text]) {
            item.text = labels[item.text]; item.width = 48; item.height = 40;
            item.textFont.pixelSize = 14; adaptedControls.push(item);
          }
        }
      }
      for (const child of children) scan(child,depth+1,serverPage,lobbyPage,chatBox);
      // Native FileDialog objects are in data, not visual children.
      for (const child of item.data || []) scan(child,depth+1,serverPage,lobbyPage,chatBox);
    }
    scan(window.contentItem,0,false,false,false);
  }
  Timer { interval: 1000; repeat: true; running: host.settingsReady; onTriggered: host.refreshCompatibility(); }
  property var fallbackButton: null
  onClientContextChanged: { bootstrapReady = false; if (clientContext) Qt.callLater(host.ensureBootstrap); }
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
  Timer {
    interval:500;repeat:true;running:host.clientContext!==null;triggeredOnStart:true
    onTriggered: {
      // Backend uses the current Lua VM; a new login gets a fresh host module.
      host.ensureBootstrap();
      const scene=Ltk.roomScene;
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
        console.log("[CardCounter] standalone UI attached");
      }
      if (!host.deckHit && (host.deckSearchTicks++ % 10 === 0)) {
        const item=host.findDeck(scene);
        if (item) {
          if (host.fallbackButton) host.fallbackButton.visible=false;
          host.deckItem=item;host.deckHit=hitComponent.createObject(item,{counter:host.popup});
          console.log("[CardCounter] original deck icon linked");
        }
      }
    }
  }
}
