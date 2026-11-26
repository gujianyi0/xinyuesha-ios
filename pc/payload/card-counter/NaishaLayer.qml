// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Spine

Item {
  id: layer
  required property var spec
  required property string resourceRoot
  property bool loop: true
  property bool ready: false
  signal finished()
  signal failed()
  onSpecChanged: {ready=false;Qt.callLater(layer.play);}
  onResourceRootChanged: {ready=false;Qt.callLater(layer.play);}
  function play() {
    if (!motion.loaded || !spec || !spec.animation) return;
    motion.clearTracks(); motion.setToSetupPose();
    motion.setAnimation(0,spec.animation,loop);
    for (const slot of spec.hideSlots || []) motion.setAttachment(slot,"");
    ready=motion.isPlaying(0);
    if (!ready) failed();
  }
  SkeletonAnimation {
    id: motion
    atlasFile: layer.resourceRoot+layer.spec.atlas
    skeletonDataFile: layer.resourceRoot+layer.spec.skeleton
    spineVersion: SpineVersion.Auto
    premultipliedAlapha: layer.spec.pma === true
    skeletonScale: layer.spec.scale*layer.height/180
    timeScale: layer.spec.speed || 1
    x: layer.width*layer.spec.x[1]+layer.spec.x[0]*layer.height/180
    y: layer.height*(1-layer.spec.y[1])-layer.spec.y[0]*layer.height/180
    rotation: -(layer.spec.angle || 0)
    // Keep the skeleton's origin. Giving it a width/height stretches its bounds.
    onSkeletonLoadFinished: ok => { if(ok) layer.play(); else layer.failed(); }
    onComplete: (track,count) => {if(!layer.loop)layer.finished();}
    Component.onCompleted: if (loaded) layer.play()
  }
  Timer { interval:4000;running:!layer.ready;onTriggered:layer.failed() }
}
