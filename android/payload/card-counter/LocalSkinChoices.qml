// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Fk
import LunarLtk

Item {
  id: manager
  required property var owner
  readonly property var scene:owner.currentScene
  property var identities: ({})
  property var registrations: null
  property var states: []
  property var targets: []
  property var availableSkins: []
  property var localChoices: ({})
  property bool preferencesReadable: true
  property string error:""
  function readChoices() {
    try {
      const data=JSON.parse(Backend.readFileFromAssets("local-skin-choices.json") || "{}");
      if(!data || typeof data!=="object" || Array.isArray(data))throw Error("Invalid choices");
      localChoices=data;preferencesReadable=true;
    }catch(_){preferencesReadable=false;error="皮肤选择读取失败，原文件已保留";}
  }
  function identity(general) {
    if(identities[general])return identities[general];
    let info=null;
    try {info=Lua.ev('(function() local g=Fk.generals['+JSON.stringify(general)+']; if g then return {trueName=g.trueName,kingdom=g.kingdom} end end)()');}catch(_){}
    if(!info || !info.trueName || typeof info.kingdom!=="string")return null;
    identities[general]=info;return info;
  }
  function sameCharacter(a,b) {
    if(a===b)return true;
    const x=identity(a),y=identity(b);
    return !!x && !!y && x.trueName===y.trueName && (x.kingdom==="god")===(y.kingdom==="god");
  }
  function registeredGenerals() {
    if(registrations)return registrations;
    let rows=[];
    try{rows=Array.from(Lua.ev('(function() local t={} for g in pairs(Fk.skin_packages or {}) do t[#t+1]=g end table.sort(t) return t end)()') || []);}catch(_){}
    if(rows.length)registrations=rows;
    return rows;
  }
  function choice(general) {
    const choices=Object.assign({},Config.enabledSkins || {},localChoices);
    // An explicit per-version selection takes precedence over inheritance.
    const keys=Object.prototype.hasOwnProperty.call(choices,general)?[general]:Object.keys(choices);
    for(const saved of keys) {
      const name=String(choices[saved] || "");
      if(!name || !sameCharacter(general,saved))continue;
      // Use the actual skin registration's general, while leaving the game's
      // photo/model general and all rules unchanged.
      try {
        if(Ltk.getSkinByName(general,name))return {general:general,name:name};
        if(Ltk.getSkinByName(saved,name))return {general:saved,name:name};
        for(const source of registeredGenerals())
          if(sameCharacter(general,source) && Ltk.getSkinByName(source,name))return {general:source,name:name};
      }catch(_){}
    }
    return null;
  }
  function findArea(photo,general) {
    const pending=Array.from(photo.children || []);
    for(let i=0;i<pending.length && i<160;i++) {
      const item=pending[i];if(!item)continue;
      if("skelData" in item && "skinName" in item && String(item.general)===general)return item;
      if(item.children)pending.push(...Array.from(item.children));
    }
    return null;
  }
  Component {
    id:overrideComponent
    Item {
      id:overrideItem
      required property var area
      required property var photo
      required property string side
      property string hero:""
      property bool retiring:false
      property var selected:null
      Binding {target:overrideItem.area;property:"general";value:overrideItem.selected?overrideItem.selected.general:"";when:!!overrideItem.selected;restoreMode:Binding.RestoreBindingOrValue}
      Binding {target:overrideItem.area;property:"skinName";value:overrideItem.selected?overrideItem.selected.name:"";when:!!overrideItem.selected;restoreMode:Binding.RestoreBindingOrValue}
    }
  }
  function release() {
    for(const state of states)retire(state);
    states=[];
  }
  function retire(state){if(!state.retiring){state.retiring=true;state.selected=null;state.destroy();}}
  function sync() {
    if(!scene || !scene.visible || Config.banChangeSkin){release();return;}
    const live=[];
    for(const model of Array.from(scene.dataModel && scene.dataModel.players || [])) {
      const photo=model && model.photoItem;if(!photo)continue;
      for(const side of ["general","deputyGeneral"]) {
        const general=String(photo[side] || "");if(!general)continue;
        let state=states.find(s=>s.photo===photo && s.side===side);
        // A replaced hero must first recover the stock binding before looking
        // for the new area. The photo identity is never overwritten.
        if(state && state.hero!==general){retire(state);state=null;}
        const selected=typeof owner.hasNaishaSkin==="function" && owner.hasNaishaSkin(general)?null:choice(general);
        if(!selected) {if(state)retire(state);continue;}
        if(!state) {
          const area=findArea(photo,general);if(!area)continue;
          state=overrideComponent.createObject(manager,{area:area,photo:photo,side:side,hero:general});
          if(!state)continue;
        }
        if(!state.selected || JSON.stringify(state.selected)!==JSON.stringify(selected))state.selected=selected;
        live.push(state);
      }
    }
    for(const state of states)if(!live.includes(state))retire(state);
    states=live;
  }
  Connections {target:Config;ignoreUnknownSignals:true;function onBanChangeSkinChanged(){manager.sync();}function onEnabledSkinsChanged(){manager.sync();}}
  onSceneChanged:{release();identities=({});registrations=null;Qt.callLater(sync);if(picker.visible)picker.close();}
  Component.onDestruction:release()
  Component.onCompleted:{readChoices();Qt.callLater(sync);}
  Timer {interval:800;repeat:true;running:!!manager.scene && manager.scene.visible;onTriggered:manager.sync()}
  function openSettings() {
    const ids=new Set();
    for(const model of Array.from(scene && scene.dataModel && scene.dataModel.players || [])) {
      const photo=model && model.photoItem;if(!photo)continue;
      for(const id of [photo.general,photo.deputyGeneral])if(id)ids.add(String(id));
    }
    targets=Array.from(ids).map(id=>({id:id,label:Lua.tr(id)+" · "+id}));
    target.currentIndex=targets.length?0:-1;updateSkins();picker.open();
  }
  function updateSkins() {
    const general=target.currentIndex>=0?targets[target.currentIndex].id:"";
    const registered=registeredGenerals();
    const rows=[];
    for(const source of registered.filter(id=>sameCharacter(general,id))) {
      for(const name of Array.from(Ltk.getSkinNamesByGeneral(source) || [])) {
        if(!rows.some(row=>row.name===name))rows.push({general:source,name:name,label:Lua.tr(name)});
      }
    }
    availableSkins=rows;skins.currentIndex=rows.length?0:-1;
    const saved=choice(general);
    if(saved){const index=rows.findIndex(row=>row.name===saved.name);if(index>=0)skins.currentIndex=index;}
  }
  function saveSelection(clear) {
    if(!preferencesReadable || target.currentIndex<0)return false;
    const general=targets[target.currentIndex].id,selected=skins.currentIndex>=0?availableSkins[skins.currentIndex]:null;
    if(!clear && !selected)return false;
    const next=Object.assign({},Config.enabledSkins || {});
    // Only save this version's choice. No network notification or remote model
    // is changed; other versions retain their explicit selections.
    next[general]=clear?"":selected.name;
    const saved=Object.assign({},localChoices);saved[general]=next[general];
    if(!Backend.writeFileToAssets("local-skin-choices.json",JSON.stringify(saved))){error="保存失败，未更改选择";return false;}
    localChoices=saved;error="";Config.enabledSkins=next;Config.saveConf();sync();return true;
  }
  Button {
    objectName:"localInGameSkinButton"
    parent:manager.scene || manager
    visible:!!manager.scene && manager.scene.visible && !Config.banChangeSkin
    text:"局内换皮";width:96;height:40;z:101
    x:parent?Math.max(4,parent.width-width-176):0;y:8
    onClicked:manager.openSettings()
  }
  Popup {
    id:picker;parent:manager.Window.window?manager.Window.window.contentItem:manager
    anchors.centerIn:parent;width:Math.min(620,parent.width-24);height:Math.min(380,parent.height-24)
    modal:true;padding:16
    ColumnLayout {
      anchors.fill:parent
      RowLayout {Layout.fillWidth:true;Label{text:"局内换皮";font.pixelSize:22;Layout.fillWidth:true}Button{text:"关闭";onClicked:picker.close()}}
      ScrollView {
        id:controls;objectName:"localSkinControls";Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:0;clip:true;contentWidth:availableWidth
        ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
        ColumnLayout {width:controls.availableWidth
      Label {text:"手动选择并保存，只影响本机显示；同名敌方沿用本机选择。";Layout.fillWidth:true;wrapMode:Text.Wrap}
      ComboBox {id:target;objectName:"localSkinGeneralChoice";model:manager.targets;textRole:"label";Layout.fillWidth:true;onActivated:manager.updateSkins()}
      ComboBox {id:skins;objectName:"localSkinChoice";model:manager.availableSkins;textRole:"label";Layout.fillWidth:true}
      Label {visible:!manager.availableSkins.length;text:"此人物暂无已注册的服务器皮肤，可在奶杀动皮中查看。";Layout.fillWidth:true;wrapMode:Text.Wrap}
      RowLayout {
        Button {objectName:"localSkinApply";text:"使用并保存";enabled:skins.currentIndex>=0;onClicked:manager.saveSelection(false)}
        Button {text:"恢复服务器显示";enabled:target.currentIndex>=0;onClicked:manager.saveSelection(true)}
      }
      Button {text:"奶杀动皮";onClicked:{picker.close();owner.openNaishaSettings();}}
      Label {text:manager.error;color:"#d0644c";wrapMode:Text.Wrap;Layout.fillWidth:true}
        }
      }
    }
  }
}
