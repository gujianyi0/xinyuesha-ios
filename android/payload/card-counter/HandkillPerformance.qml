// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Spine

Item {
  id: root
  objectName: "fkHandkillPerformance"
  required property url resourceBase
  required property string general
  required property string skillName
  property string animationName: "play"
  property var followupAnimations: []
  property real designWidth: 1334
  property real designHeight: 750
  property real offsetX: 0
  property real offsetY: 0
  property var anchorPhoto: null
  property bool originalJiangweiLayout: false
  property url frameBase: ""
  property int maximumMs: 16000
  property bool started: false
  property bool disposed: false
  property int sequenceIndex: 0
  property string lastError: ""
  signal finished(bool completed)

  readonly property point effectCentre: anchorPhoto && parent ?
    parent.mapFromItem(anchorPhoto,anchorPhoto.width/2,anchorPhoto.height/2) : Qt.point(parent.width/2,0)
  width: anchorPhoto ? Math.min(260,anchorPhoto.width*1.8) : parent.width
  height: originalJiangweiLayout ? parent.height :
    anchorPhoto ? Math.min(300,anchorPhoto.height*1.4) : Math.min(parent.height * 0.55, 300)
  x: anchorPhoto ? effectCentre.x-width/2 : 0
  y: originalJiangweiLayout ? 0 : anchorPhoto ? effectCentre.y-height/2 : (parent.height - height) * 0.32
  z: 7800
  // v1 keeps the original animation inside a bounded, noninteractive band.
  // Exported setup bounds can include offscreen bones and are not a viewport.
  // Original Jiangwei exports use a 1334-wide stage and carry their own
  // animated clipping polygon. Do not replace it with a fitted rectangle.
  readonly property real artworkScale: originalJiangweiLayout ? width / 1334 :
    Math.min(width / (anchorPhoto ? 200 : designWidth), height / (anchorPhoto ? 220 : designHeight))

  function finish(ok, reason) {
    if (disposed) return;
    disposed = true;
    lastError = reason || "";
    loadTimeout.stop(); playTimeout.stop();
    motion.clearTracks(); visible = false;
    if (frameLoader.item) frameLoader.item.clearTracks();
    console.log("[HandkillPerformance] " + (ok ? "complete " : "stopped ") + general + ":" + skillName + " " + lastError);
    Qt.callLater(function() { root.finished(ok); });
  }
  function play(name) {
    motion.setAnimation(0, name, false);
    if (!motion.isPlaying(0)) { finish(false, "animation unavailable: " + name); return false; }
    return true;
  }
  function begin() {
    if (disposed || started || !motion.loaded) return;
    if (frameLoader.active && (!frameLoader.item || !frameLoader.item.loaded)) return;
    motion.clearTracks(); motion.setToSetupPose();
    started = true;
    loadTimeout.stop(); playTimeout.restart();
    play(animationName);
    if (!disposed && frameLoader.item) {
      frameLoader.item.setToSetupPose();
      frameLoader.item.setAnimation(0,"play1",false);
      if (!frameLoader.item.isPlaying(0)) finish(false,"frame animation unavailable");
    }
  }
  function loaded() {
    if (!motion.loaded || frameLoader.active && (!frameLoader.item || !frameLoader.item.loaded)) return;
    loadTimeout.stop(); Qt.callLater(begin);
  }
  EffectLayer {
    sourceItem: root
    clip: true
  Item {
    visible: root.started && !root.disposed
    x: root.width / 2 + root.offsetX * root.artworkScale
    y: root.height / 2 + root.offsetY * root.artworkScale
    scale: root.artworkScale
    SkeletonAnimation {
      id: motion
      objectName: "handkillSkeleton"
      atlasFile: root.resourceBase + ".atlas"
      skeletonDataFile: root.resourceBase + ".skel"
      skeletonScale: 1
      spineVersion: SpineVersion.Auto
      premultipliedAlapha: false
      onSkeletonLoadFinished: function(ok) {
        if (ok) root.loaded();
        else root.finish(false, "skeleton load failed");
      }
      onComplete: function(trackIndex, loopCount) {
        if (trackIndex !== 0 || !root.started || root.disposed) return;
        // The callback must unwind before changing tracks or destroying a player.
        Qt.callLater(function() {
          if (root.disposed) return;
          if (root.sequenceIndex < root.followupAnimations.length)
            root.play(root.followupAnimations[root.sequenceIndex++]);
          else root.finish(true, "");
        });
      }
    }
    Loader {
      id: frameLoader
      active: String(root.frameBase).length > 0
      sourceComponent: Component {
        SkeletonAnimation {
          property bool holding: false
          objectName: "handkillFrameSkeleton"
          atlasFile: root.frameBase + ".atlas"
          skeletonDataFile: root.frameBase + ".skel"
          skeletonScale: 1
          spineVersion: SpineVersion.Auto
          premultipliedAlapha: false
          onSkeletonLoadFinished: function(ok) {
            if (ok) Qt.callLater(root.loaded);
            else root.finish(false,"frame skeleton load failed");
          }
          onComplete: function(trackIndex, loopCount) {
            if (trackIndex !== 0 || holding || root.disposed || !root.started) return;
            holding = true;
            Qt.callLater(function() {
              if (!root.disposed) frameLoader.item.setAnimation(0,"play2",true);
            });
          }
        }
      }
    }
  }
  }
  Timer { id: loadTimeout; interval: 12000; running: true; onTriggered: root.finish(false, "load timeout") }
  Timer { id: playTimeout; interval: root.maximumMs; onTriggered: root.finish(false, "completion timeout") }
}
