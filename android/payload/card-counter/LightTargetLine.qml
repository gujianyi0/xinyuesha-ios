// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Spine

Item {
  id: root
  objectName: "lightTargetLine"
  required property point origin
  required property point destination
  required property url imageSource
  // The original sprite is a ten-frame dragon head, not a whole dragon.
  property bool originalFrames: false
  // OL's original skeleton retains its eight attachment changes, including
  // the longer fifth frame. Do not flatten it to ten equal-duration frames.
  property bool olOriginalFrames: false
  property bool olReady: false
  property bool disposed: false
  property bool autoDispose: true
  property real progress: 0
  readonly property real distance: Math.hypot(destination.x-origin.x, destination.y-origin.y)
  readonly property real extend: Math.sin(Math.min(1, progress*2)*Math.PI/2)
  readonly property real retract: Math.sin(Math.max(0, progress*2-1)*Math.PI/2)
  readonly property real headPosition: distance*extend
  readonly property real tailPosition: distance*retract
  readonly property real headWidth: Math.min(153, distance*0.85)
  signal finished(bool completed)
  z: 100
  x: origin.x
  y: origin.y
  opacity: Math.min(1, progress*12, (1-progress)*10)
  transform: Rotation {
    angle: Math.atan2(root.destination.y-root.origin.y, root.destination.x-root.origin.x)*180/Math.PI
  }

  function finish(completed) {
    if (disposed) return;
    disposed = true;
    travel.stop();
    loadTimeout.stop();
    visible = false;
    // Keep native callbacks off the destruction stack.
    Qt.callLater(function() {
      root.finished(completed);
      if (root.autoDispose) root.destroy();
    });
  }

  EffectLayer {
    sourceItem: root
  Loader {
    active: root.olOriginalFrames
    x: root.headPosition - root.headWidth * 0.5
    y: 0
    scale: root.headWidth / 256
    visible: root.olReady && !root.disposed
    sourceComponent: Component {
      SkeletonAnimation {
        objectName: "olTargetLineSkeleton"
        atlasFile: String(root.imageSource).slice(0, -4) + ".atlas"
        skeletonDataFile: String(root.imageSource).slice(0, -4) + ".skel"
        skeletonScale: 1
        spineVersion: SpineVersion.Auto
        premultipliedAlapha: false
        timeScale: 0.625
        // Original dragon head faces left; the indication moves right.
        transform: Scale { xScale: -1 }
        onSkeletonLoadFinished: function(ok) {
          if (!ok) { root.finish(false); return; }
          Qt.callLater(function() {
            if (root.disposed) return;
            clearTracks(); setToSetupPose(); setAnimation(0, "play", true);
            if (!isPlaying(0)) { root.finish(false); return; }
            root.olReady = true;
            loadTimeout.stop();
          });
        }
      }
    }
  }
  Timer {
    id: loadTimeout
    interval: 5000
    running: root.olOriginalFrames && !root.olReady && !root.disposed
    onTriggered: root.finish(false)
  }

  Rectangle {
    x: root.tailPosition; y: -2
    width: Math.max(0, root.headPosition-root.tailPosition)
    height: 4
    gradient: Gradient {
      GradientStop { position: 0; color: "#00d28d24" }
      GradientStop { position: 0.4; color: "#d2ebb14a" }
      GradientStop { position: 0.5; color: "#ffffedaa" }
      GradientStop { position: 0.6; color: "#d2ebb14a" }
      GradientStop { position: 1; color: "#00d28d24" }
    }
  }
  AnimatedSprite {
    visible: root.originalFrames && root.distance > 1
    source: root.originalFrames ? root.imageSource : ""
    x: root.headPosition - width*0.91
    y: -height/2
    width: root.headWidth
    height: width*120/255
    frameCount: 10
    frameWidth: 255
    frameHeight: 120
    // Original: 100ms/frame and 1000ms/line. Slow both by 1.6x.
    frameDuration: 160
    interpolate: false
    running: visible
    transform: Scale { origin.x: root.headWidth/2; xScale: -1 }
  }
  Image {
    // Older independently downloaded packs remain compatible.
    visible: !root.originalFrames && !root.olOriginalFrames
    source: (root.originalFrames || root.olOriginalFrames) ? "" : root.imageSource
    x: root.headPosition-width
    y: -height/2
    width: Math.min(153, root.distance*0.85)
    height: width*0.3
    fillMode: Image.PreserveAspectFit
  }
  }
  NumberAnimation on progress {
    id: travel
    from: 0; to: 1; duration: 1600
    running: !root.olOriginalFrames || root.olReady
    onFinished: root.finish(true)
  }
}
