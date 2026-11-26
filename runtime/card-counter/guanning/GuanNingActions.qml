// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import Spine
import ".." as Counter

Item {
  id: root
  required property var photo
  required property var scene
  property var stockArea: null
  property string general: "guanning"
  property string skinName: "墨韵荷香"
  readonly property bool guanNingActionAdapter: true
  property bool ready: false
  property string activeAction: ""
  property string pendingAction: ""
  property var pendingContext: ({})
  property string lastError: ""
  property int startedCount: 0
  property int completedCount: 0
  property int generation: 0
  property point origin: Qt.point(0,0)
  property real actionScale: 1
  property var targetIds: []
  property var trails: []
  property var preview: null
  property bool showPreviewButton: true
  property real previousOpacity: 1
  required property url resourceRoot
  signal actionStarted(string action)
  signal actionCompleted(string action)

  function playAction(action, context) {
    if (action !== "attack" && action !== "skill") return false;
    if (activeAction === "skill" && action === "attack") return false;
    pendingAction = action; pendingContext = context || {};
    if (!ready) return true;
    return startPending();
  }
  function startPending() {
    if (!ready || !pendingAction) return false;
    const action = pendingAction, context = pendingContext;
    pendingAction = ""; ++generation;
    const p = photo.mapToItem(scene, photo.width*.5, photo.height*.5);
    actionScale = Math.min(scene.height*.65/890, scene.width*.56/1370);
    origin = Qt.point(Math.max(670*actionScale, Math.min(scene.width-670*actionScale,p.x)),
      Math.max(480*actionScale, Math.min(scene.height-430*actionScale,p.y)));
    targetIds = Array.from(context.targets || []);
    activeAction = action; lastError = "";
    motion.clearTracks(); motion.setToSetupPose();
    motion.setAnimation(0, action === "attack" ? "gongji" : "jineng", false);
    if (!motion.isPlaying(0)) {
      lastError = "原版动作未能开始播放"; activeAction = ""; return false;
    }
    startedCount++; actionStarted(action);
    console.log("[GuanNingActions] start " + (action === "attack" ? "gongji" : "jineng"));
    watchdog.interval = action === "attack" ? 4000 : 5200; watchdog.restart();
    if (action === "attack" && targetIds.length) launch.restart();
    return true;
  }
  function finishAction(expected, completed) {
    if (expected !== generation || !activeAction) return;
    const action = activeAction;
    activeAction = ""; launch.stop(); watchdog.stop();
    if (completed) {
      completedCount++; actionCompleted(action);
      console.log("[GuanNingActions] complete " + action);
    }
  }
  function launchTrails() {
    trails = trails.filter(t => {try{return t && !!t.parent;}catch(_){return false;}});
    const players = scene.dataModel && scene.dataModel.players || [];
    for (const id of targetIds.slice(0,8)) {
      const model = Array.from(players).find(p => String(p.playerid !== undefined ? p.playerid : p.id) === String(id));
      const target = model && model.photoItem;
      if (!target || !target.visible || target === photo) continue;
      const end = target.mapToItem(scene,target.width*.5,target.height*.5);
      const start = Qt.point(origin.x-190*actionScale,origin.y-80*actionScale);
      const effect = trailComponent.createObject(scene,{startPoint:start,endPoint:end,targetWidth:target.width*.95, resourceRoot:root.resourceRoot});
      if (effect) {
        trails.push(effect);
        effect.disposed.connect(function(){ root.trails=root.trails.filter(t=>t!==effect); });
      }
    }
  }
  Component { id: trailComponent; GuanNingTrail {} }
  Button {
    objectName:"guanningLocalPreviewButton"
    visible:root.showPreviewButton
    parent:root.scene;z:9000
    x:(parent.width-width)*.5;y:4
    text:"墨韵动作预览"
    onClicked:{
      if (!root.preview) {
        const component=Qt.createComponent("GuanNingPreview.qml");
        if(component.status===Component.Ready)root.preview=component.createObject(root.scene,{resourceRoot:root.resourceRoot});
      }
      if(root.preview)root.preview.open();
    }
  }
  Timer { id: launch; interval:500; onTriggered:root.launchTrails() }
  Timer { id: watchdog; onTriggered:{ root.lastError="动作结束信号超时"; root.finishAction(root.generation,false); } }
  Item {
    id: stage
    parent: root.scene
    x: root.origin.x; y: root.origin.y
    z: 8000; scale:root.actionScale
    visible: !!root.activeAction
    Counter.EffectLayer {
      sourceItem: stage
    SkeletonAnimation {
      id: motion
      atlasFile: root.resourceRoot + "chuchang2.atlas"
      skeletonDataFile: root.resourceRoot + "chuchang2.skel"
      skeletonScale:1
      spineVersion:SpineVersion.Auto
      premultipliedAlapha:false
      onSkeletonLoadFinished: function(ok) {
        root.ready=ok;
        if (!ok) {root.lastError="原版动作骨架加载失败";console.warn("[GuanNingActions] skeleton load failed");}
        else {console.log("[GuanNingActions] skeleton ready");Qt.callLater(root.startPending);}
      }
      onComplete: function(trackIndex,loopCount) {
        if (trackIndex!==0 || !root.activeAction) return;
        const expected=root.generation;
        Qt.callLater(function(){root.finishAction(expected,true);});
      }
    }
    }
  }
  Component.onCompleted: {
    if (stockArea) {
      previousOpacity=stockArea.opacity;
      stockArea.opacity=Qt.binding(function(){return root.activeAction ? 0 : root.previousOpacity;});
    }
  }
  Component.onDestruction: {
    try { if (stockArea) stockArea.opacity=previousOpacity; } catch (_) {}
    for (const trail of trails) {try {if(trail && typeof trail.destroy==="function")trail.destroy();}catch(_) {}}
    try {if(preview && typeof preview.destroy==="function")preview.destroy();}catch(_) {}
  }
}
