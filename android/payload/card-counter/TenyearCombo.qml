// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Spine

Item {
  id: root
  objectName: "fkTenyearCombo"
  required property url resourceBase
  required property string general
  required property string skillName
  property bool started: false
  property bool disposed: false
  property string lastError: ""
  signal finished(bool completed)

  width: parent.width
  height: Math.min(parent.height * 0.55, 300)
  y: (parent.height - height) * 0.32
  z: 7800
  // A bounded banner rather than a full-table overlay. Leave the native
  // skeleton item dimensionless so the engine preserves its world origin.
  readonly property real artworkScale: Math.min(width / 1700, height / 620)

  function finish(completed, reason) {
    if (disposed) return;
    disposed = true;
    lastError = reason || "";
    loadTimeout.stop();
    playTimeout.stop();
    motion.clearTracks();
    visible = false;
    console.log("[TenyearCombo] " + (completed ? "complete " : "stopped ") + general + (reason ? " " + reason : ""));
    // Emit outside the native Spine event callback: destroying its parent
    // synchronously while a native listener is on the stack is unsafe.
    Qt.callLater(function() { root.finished(completed); });
  }

  function begin() {
    if (disposed || started || !motion.loaded) return;
    motion.clearTracks();
    motion.setToSetupPose();
    motion.setAnimation(0, "play", false);
    if (!motion.isPlaying(0)) {
      finish(false, "play animation unavailable");
      return;
    }
    started = true;
    loadTimeout.stop();
    playTimeout.restart();
    console.log("[TenyearCombo] start " + general + " skill=" + skillName);
  }

  EffectLayer {
    sourceItem: root
    clip: true
  Item {
    x: root.width * 0.5
    y: root.height * 0.55
    scale: root.artworkScale
    SkeletonAnimation {
      id: motion
      objectName: "tenyearComboSkeleton"
      atlasFile: root.resourceBase + ".atlas"
      skeletonDataFile: root.resourceBase + ".skel"
      skeletonScale: 1
      spineVersion: SpineVersion.Auto
      premultipliedAlapha: false
      onSkeletonLoadFinished: function(ok) {
        if (ok) Qt.callLater(root.begin);
        else root.finish(false, "skeleton load failed");
      }
      onComplete: function(trackIndex, loopCount) {
        if (trackIndex === 0 && root.started) root.finish(true, "");
      }
    }
  }
  }
  Timer { id: loadTimeout; interval: 12000; running: true; onTriggered: root.finish(false, "load timeout") }
  Timer { id: playTimeout; interval: 4200; onTriggered: root.finish(false, "completion timeout") }
}
