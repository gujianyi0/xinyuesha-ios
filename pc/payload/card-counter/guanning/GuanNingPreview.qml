// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Spine
Dialog {
 id:root
 required property url resourceRoot
 parent:Overlay.overlay
 property alias actionPlayer:actions
 title:"墨韵荷香 · 本机动作预览"
 width:parent.width*.94;height:parent.height*.94
 x:(parent.width-width)*.5;y:(parent.height-height)*.5
 modal:true;closePolicy:Popup.NoAutoClose
 background:Rectangle{color:"#14292e";border.color:"#9f8757";radius:10}
 header:Label{text:root.title;color:"#f2e2c0";font.pixelSize:18;padding:12}
 contentItem:ColumnLayout{
  spacing:6
  Label{Layout.fillWidth:true;text:"使用独立资源补丁中的原版攻击、技能、锦鲤轨迹与命中特效。此预览不发送游戏操作。";color:"#d5dedb";font.pixelSize:13;wrapMode:Text.Wrap}
  Item{
   id:arena;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
   property var dataModel:({players:[{playerid:2,photoItem:target}]})
   Rectangle{anchors.fill:parent;color:"#263d41";radius:8}
   Rectangle{id:target;x:arena.width*.12;y:arena.height*.15;width:arena.width*.10;height:arena.height*.40;color:"#34545b";border.color:"#d9c496";Text{anchors.centerIn:parent;text:"目标";color:"white"}}
   Item{
    id:photo;width:arena.width*.14;height:arena.height*.65;x:arena.width-width-12;y:arena.height-height-8;clip:true
    Rectangle{anchors.fill:parent;color:"#172b31";border.color:"#d9c496"}
    SkeletonAnimation{
     id:idle;x:photo.width*.5;y:photo.height*.5
     scale:Math.min(photo.width/250,photo.height/300)
     atlasFile:root.resourceRoot + "daiji2.atlas";skeletonDataFile:root.resourceRoot + "daiji2.json"
     skeletonScale:1;spineVersion:SpineVersion.Auto;premultipliedAlapha:false
     onSkeletonLoadFinished:function(ok){if(ok)setAnimation(0,"play",true);}
    }
   }
   GuanNingActions{id:actions;resourceRoot:root.resourceRoot;photo:photo;scene:arena;stockArea:idle;showPreviewButton:false}
  }
  Label{Layout.fillWidth:true;text:actions.lastError||(!actions.ready?"正在加载原版骨架…":actions.activeAction==="attack"?"攻击播放中":actions.activeAction==="skill"?"技能播放中":"已就绪 · 完整播放 "+actions.completedCount+" 次");color:actions.lastError?"#f6a19a":"#cce4cf";font.pixelSize:13}
  RowLayout{
   Button{objectName:"guanningAttackPreview";text:"攻击";enabled:actions.ready;onClicked:actions.playAction("attack",{targets:[2]})}
   Button{objectName:"guanningSkillPreview";text:"技能";enabled:actions.ready;onClicked:actions.playAction("skill",{})}
   Item{Layout.fillWidth:true}
   Button{objectName:"guanningClosePreview";text:"关闭";onClicked:root.close()}
  }
 }
 onClosed:{actions.finishAction(actions.generation,false);}
}
