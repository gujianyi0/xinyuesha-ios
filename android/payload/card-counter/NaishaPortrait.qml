// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

Item {
  id: portrait
  required property var skin
  required property string resourceRoot
  property bool active: true
  property string action: ""
  property bool broken: false
  property bool layersActive: false
  property int generation: 0
  property int loadGeneration: 0
  readonly property bool ready: idle.item && idle.item.ready && !broken
  signal actionStarted(string kind)
  anchors.fill: parent
  clip: true
  function playAction(kind) {
    if (!active || broken || !ready || !skin[kind]) return false;
    finish();const epoch=generation;
    // Recreate each action layer. Rebinding atlas and skeleton separately can
    // briefly pair files from two skins and poison an asynchronous load.
    Qt.callLater(function(){if(epoch!==generation || !portrait.active)return;action=kind;actionLayer.active=true;deadline.restart();});
    return true;
  }
  function finish() {++generation;actionLayer.active=false;action="";deadline.stop();}
  function resetLayers() {
    finish();broken=false;layersActive=false;const epoch=++loadGeneration;
    Qt.callLater(function(){if(epoch===loadGeneration)layersActive=true;});
  }
  onActiveChanged: if (!active) finish()
  onSkinChanged: resetLayers()
  onResourceRootChanged: resetLayers()
  Component.onCompleted: resetLayers()
  Loader {
    anchors.fill: parent;active:portrait.active && portrait.layersActive && !!portrait.skin.background && !portrait.broken
    sourceComponent: NaishaLayer {
      spec:portrait.skin.background;resourceRoot:portrait.resourceRoot
      onFailed: visible=false
    }
  }
  Loader {
    id:idle;anchors.fill:parent;active:portrait.active && portrait.layersActive && !portrait.broken
    visible:portrait.ready && !(actionLayer.item && actionLayer.item.ready)
    sourceComponent: NaishaLayer {
      spec:portrait.skin.idle;resourceRoot:portrait.resourceRoot
      onFailed: portrait.broken=true
    }
  }
  Loader {
    id:actionLayer;anchors.fill:parent;active:false
    visible:item && item.ready
    sourceComponent: NaishaLayer {
      spec:portrait.skin[portrait.action] || portrait.skin.idle;resourceRoot:portrait.resourceRoot;loop:false
      onReadyChanged: if(ready)portrait.actionStarted(portrait.action)
      onFailed: portrait.finish()
      onFinished: portrait.finish()
    }
  }
  Timer {id:deadline;interval:5000;onTriggered:portrait.finish()}
}
