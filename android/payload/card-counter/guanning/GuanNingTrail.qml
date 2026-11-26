// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Spine
import ".." as Counter
Item {
  id:root
  required property url resourceRoot
  required property point startPoint
  required property point endPoint
  property bool impactActive:false
  property bool finished:false
  property bool disposing:false
  signal disposed()
  property real distance:Math.hypot(endPoint.x-startPoint.x,endPoint.y-startPoint.y)
  property real targetWidth:125
  property real trailScale:distance/1269.93212
  property real direction:Math.atan2(endPoint.y-startPoint.y,endPoint.x-startPoint.x)
  z:8100
  function dispose(){if(disposing)return;disposing=true;disposed();destroy();}
  function beginImpact() {
    if (finished || impactActive) return;
    impactActive=true;
    if (impact.loaded) impact.setAnimation(0,"play",false);
  }
  Counter.EffectLayer {
    sourceItem: root
  Item {
    x:(root.startPoint.x+root.endPoint.x)*.5
    y:(root.startPoint.y+root.endPoint.y)*.5
    rotation:root.direction*180/Math.PI
    scale:root.trailScale
    visible:!root.impactActive
    SkeletonAnimation {
    id:trail
    // Atlas-trimmed animated bounds, centered before rotation and scaling.
    x:473.42418;y:-0.59846
    atlasFile:root.resourceRoot + "shouji2.atlas"
    skeletonDataFile:root.resourceRoot + "shouji2.json"
    skeletonScale:1;spineVersion:SpineVersion.Auto;premultipliedAlapha:false
    onSkeletonLoadFinished:function(ok){if(ok){setAnimation(0,"play",false);console.log("[GuanNingActions] koi trail started");}else root.beginImpact();}
    onComplete:function(trackIndex,loopCount){if(trackIndex===0)Qt.callLater(root.beginImpact);}
    }
  }
  Item {
    x:root.endPoint.x;y:root.endPoint.y
    scale:root.targetWidth/376.05
    visible:root.impactActive
    SkeletonAnimation {
    id:impact
    x:-2.875;y:3.45
    atlasFile:root.resourceRoot + "shouji.atlas"
    skeletonDataFile:root.resourceRoot + "shouji.json"
    skeletonScale:1;spineVersion:SpineVersion.Auto;premultipliedAlapha:false
    onSkeletonLoadFinished:function(ok){if(ok&&root.impactActive)setAnimation(0,"play",false);}
    onComplete:function(trackIndex,loopCount){if(trackIndex===0){root.finished=true;console.log("[GuanNingActions] koi impact complete");Qt.callLater(root.dispose);}}
    }
  }
  }
  Timer{interval:4000;running:true;onTriggered:root.dispose()}
}
