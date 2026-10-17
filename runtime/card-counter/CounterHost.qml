// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
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
  onClientContextChanged: if (clientContext) Qt.callLater(host.ensureBootstrap)
  function ensureBootstrap() {
    // C++ publishes its process-global ClientInstance before its worker thread
    // finishes constructing the Lua VM. The QML context is set only afterwards.
    // Never call Backend.evalLuaExp through that partially constructed client.
    if (typeof ClientInstance === "undefined" || !ClientInstance) return false;
    try {
      return Lua.ev('(function() if not ClientInstance or not Client or not Fk then return false end if not FkCardCounterRuntimeReady then dofile("card-counter/bootstrap.lua"); FkCardCounterRuntimeReady=true; if fk and fk.qInfo then fk.qInfo("[CardCounter] client runtime ready") end end return true end)()') === true;
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
  Timer {
    interval:250;repeat:true;running:host.clientContext!==null;triggeredOnStart:true
    onTriggered: {
      // Backend uses the current Lua VM; a new login gets a fresh host module.
      host.ensureBootstrap();
      const scene=Ltk.roomScene;
      if (!scene || !scene.dataModel) {host.currentScene=null;return;}
      if (scene!==host.currentScene) {
        const component=Qt.createComponent("CardCounter.qml");
        if (component.status!==Component.Ready) {console.warn("[CardCounter] "+component.errorString());return;}
        host.popup=component.createObject(scene,{roomModel:scene.dataModel});
        if (!host.popup) return;
        host.currentScene=scene;
        host.deckItem=null;host.deckHit=null;
        console.log("[CardCounter] standalone UI attached");
      }
      if (!host.deckHit) {
        const item=host.findDeck(scene);
        if (item) {
          host.deckItem=item;host.deckHit=hitComponent.createObject(item,{counter:host.popup});
          console.log("[CardCounter] original deck icon linked");
        }
      }
    }
  }
}
