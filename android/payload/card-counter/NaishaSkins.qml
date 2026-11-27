// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Fk

Item {
  id: manager
  required property var owner
  readonly property string packId:"奶杀动皮-v1"
  readonly property string dataPath:"resource_pak/"+packId+"/packages/freekill-core/image/xinyuesha-naisha/"
  readonly property string resourceRoot:String(Cpp.path).replace(/\/$/,"")+"/"+dataPath
  property var catalog: []
  property var choices: ({})
  property var states: []
  property string error:""
  property bool loaded:false
  property var identities: ({})
  property var skinList: []
  property var targets: []
  readonly property var scene:owner.currentScene
  function identity(general) {
    if (Object.prototype.hasOwnProperty.call(identities,general)) return identities[general];
    let info=null;
    try {info=Lua.ev('(function() local g=Fk.generals['+JSON.stringify(general)+']; if not g then return nil end return {name=g.name,trueName=g.trueName,kingdom=g.kingdom,label=Fk:translate(g.name),base=Fk:translate(g.trueName)} end)()');} catch (_) {}
    identities[general]=info;return info;
  }
  function matches(general,skin) {
    const info=identity(general);if(!info || !skin)return false;
    const plain=s=>String(s || "").replace(/<[^>]*>/g,"").replace(/\s/g,"");
    const character=plain(skin.character),divine=character.startsWith("神");
    if((info.kingdom==="god")!==divine)return false;
    const source=identity(skin.sourceGeneral);
    if(source && info.trueName===source.trueName && (source.kingdom==="god")===divine)return true;
    return general===skin.sourceGeneral || plain(info.label)===character ||
      plain(info.base)===(divine?character.slice(1):character);
  }
  function selectedSkin(general) {
    // Explicit restoration overrides a family choice. Older per-ID files stay valid.
    if(Object.prototype.hasOwnProperty.call(choices,general))
      return catalog.find(s=>s.id===choices[general] && matches(general,s)) || null;
    for(const saved of Object.keys(choices)) {
      const skin=catalog.find(s=>s.id===choices[saved]);
      if(skin && matches(saved,skin) && matches(general,skin))return skin;
    }
    return null;
  }
  function roomGenerals() {
    const result=[];
    for(const model of Array.from(scene && scene.visible && scene.dataModel && scene.dataModel.players || [])) {
      const photo=model && model.photoItem;if(!photo)continue;
      for(const id of [String(photo.general || ""),String(photo.deputyGeneral || "")])
        if(id && !result.includes(id))result.push(id);
    }
    return result;
  }
  function updatePicker() {
    const room=roomGenerals();
    skinList=room.length?catalog.filter(s=>room.some(g=>matches(g,s))):catalog;
    const saved=room.map(g=>selectedSkin(g)).find(s=>!!s);
    const index=saved?skinList.findIndex(s=>s.id===saved.id):-1;
    skins.currentIndex=index>=0?index:skinList.length?0:-1;
    updateTargets();
  }
  function updateTargets() {
    let generals=roomGenerals();
    if(!generals.length)try{generals=Array.from(Lua.ev('(function() local t={} for id in pairs(Fk.generals) do t[#t+1]=id end table.sort(t) return t end)()') || []);}catch(_){}
    targets=generals.filter(g=>matches(g,picker.selected)).map(g=>({id:g,label:String(identity(g).label)+" · "+g}));
    target.currentIndex=targets.length?0:-1;
  }
  function readChoices() {
    try {
      const data=JSON.parse(Backend.readFileFromAssets("naisha-skins.json") || "{}");
      if (!data || typeof data!=="object" || Array.isArray(data)) throw Error("Bad preferences");
      choices=data;
    } catch (_) {error="动皮选择读取失败，原文件已保留";}
  }
  function reload() {
    release(); catalog=[];loaded=false;
    if (!(Config.enabledResourcePacks || []).includes(packId) || typeof Backend.readJsonObjectFromFile!=="function") return;
    const data=Backend.readJsonObjectFromFile(dataPath+"catalog.json");
    if (data && data.schema===1 && data.skins && data.id===packId) {
      catalog=Array.from(data.skins);loaded=true;Qt.callLater(manager.sync);
    }
  }
  function choose(general,skin) {
    general=String(general).trim();
    if (!general) {error="请填写目标武将 ID";return false;}
    if (skin) {
      if (!identity(general)) {error="客户端没有此武将，请选择当前对局中的武将";return false;}
      if (!matches(general,skin)) {error="人物身份不一致，未替换";return false;}
    }
    const next=Object.assign({},choices);
    next[general]=skin?skin.id:"";
    if (!Backend.writeFileToAssets("naisha-skins.json",JSON.stringify(next))) {error="保存失败，未更改选择";return false;}
    choices=next;error="";sync();return true;
  }
  function release() {
    for (const state of states) releaseState(state);
    states=[];
  }
  function releaseState(state) {
    try {
      if (state.loader) state.loader.opacity=state.opacity;
      if (state.slot) {state.slot.retiring=true;state.slot.destroy();}else if(state.effect)state.effect.destroy();
    } catch (_) {}
  }
  function findArea(photo,general) {
    const pending=Array.from(photo.children || []);
    for(let i=0;i<pending.length && i<160;i++) {
      const item=pending[i];if(!item)continue;
      if ("skelData" in item && String(item.general)===general)return item;
      if(item.children)pending.push(...Array.from(item.children));
    }
    return null;
  }
  Component { id:portraitComponent;NaishaPortrait{} }
  Component {
    id:portraitSlot
    Item {
      id: replacementSlot
      objectName:"naishaPortraitSlot"
      required property var photo
      required property string general
      required property bool splitMask
      property var stockLoader: null
      property var replacement: null
      property bool retiring: false
      // Hiding a stock portrait leaves its video/skeleton and decoded textures
      // alive. Unload only after the replacement is ready. Binding restores
      // the original active binding/value on failure, disable or room exit.
      Binding {
        target: replacementSlot.stockLoader
        property: "active"
        value: false
        when: !replacementSlot.retiring && !!replacementSlot.stockLoader && !!replacementSlot.replacement && replacementSlot.replacement.ready
        restoreMode: Binding.RestoreBindingOrValue
      }
      clip:true
      width:parent ? parent.width/(splitMask && photo.deputyGeneral ? 2 : 1) : 0
      height:parent ? parent.height : 0
      x:splitMask && general===String(photo.deputyGeneral) ? width : 0
    }
  }
  function photoSurface(photo) {
    // Stock portraits render a hidden, double-resolution SkinArea through an
    // OpacityMask. Draw the replacement on that mask's visible surface, below
    // the existing name/HP/interaction siblings. Native skeletons must not be
    // nested inside the mask's hidden offscreen source on Android.
    if (!("photoMask" in photo)) return null;
    return Array.from(photo.children || []).find(c=>
      "maskSource" in c && c.maskSource===photo.photoMask) || null;
  }
  function sync() {
    if (!loaded || !scene || !scene.visible || Config.banChangeSkin) {release();return;}
    const live=[];
    for(const model of Array.from(scene.dataModel && scene.dataModel.players || [])) {
      const photo=model && model.photoItem;if(!photo)continue;
      for(const general of new Set([String(photo.general || ""),String(photo.deputyGeneral || "")])) {
        if(!general)continue;
        const skin=selectedSkin(general);if(!skin)continue;
        const area=findArea(photo,general);if(!area)continue;
        const changed=states.filter(s=>s.area===area && (s.skin!==skin.id || s.general!==general));
        for(const old of changed)releaseState(old);
        states=states.filter(s=>!changed.includes(s));
        let state=states.find(s=>s.area===area && s.skin===skin.id && s.general===general);
        if (!state) {
          const loader=Array.from(area.children || []).find(c=>"sourceComponent" in c && "item" in c);
          const surface=photoSurface(photo);
          const slot=portraitSlot.createObject(surface || area,{photo:photo,general:general,splitMask:!!surface,stockLoader:loader || null,visible:false});
          if(!slot)continue;
          const effect=portraitComponent.createObject(slot,{skin:skin,resourceRoot:resourceRoot});
          if(!effect){slot.destroy();continue;}
          slot.replacement=effect;
          slot.visible=Qt.binding(()=>effect.ready);
          state={area:area,photo:photo,general:general,skin:skin.id,slot:slot,effect:effect,loader:loader,opacity:loader?loader.opacity:1};
        }
        if(state.loader)state.loader.opacity=state.effect.ready?0:state.opacity;
        live.push(state);
      }
    }
    for(const old of states)if(!live.includes(old)) releaseState(old);
    states=live;
  }
  function route(command,data) {
    if(!scene || !scene.visible || !data || Config.banChangeSkin)return;
    const attack=command==="Fk.GuanNingSkinAction" && data.action==="attack";
    const skill=command==="Animate" && ["InvokeSkill","InvokeUltSkill"].includes(data.type);
    if(!attack && !skill)return;
    for(const state of states) {
      if (String(state.photo.playerid)!==String(data.player))continue;
      if (skill && !owner.generalOwnsSkill(state.general,data.name))continue;
      state.effect.playAction(attack?"attack":"skill");
    }
  }
  Connections {target:Mediator;function onCommandGot(sender,command,data){manager.route(command,data);}}
  Connections {target:Config;function onEnabledResourcePacksChanged(){manager.reload();}function onBanChangeSkinChanged(){manager.sync();}}
  Connections {target:manager.scene;ignoreUnknownSignals:true;function onVisibleChanged(){manager.sync();}}
  onSceneChanged:{release();identities=({});Qt.callLater(manager.sync);if(picker.visible)picker.close();}
  Component.onCompleted:{readChoices();Qt.callLater(manager.reload);}
  Component.onDestruction:release()
  Timer {interval:800;repeat:true;running:manager.loaded && !!manager.scene && Object.keys(manager.choices).length>0;onTriggered:manager.sync()}
  function openSettings(){reload();updatePicker();picker.open();}
  // A small action beside the stock room menu, outside the portrait/effect tree.
  Button {
    objectName:"naishaInGameSkinButton"
    parent:manager.scene || manager
    visible:!!manager.scene && manager.scene.visible && manager.loaded && !Config.banChangeSkin
    text:"局内换皮";width:96;height:40;z:101
    x:parent ? Math.max(4,parent.width-width-176) : 0;y:8
    onClicked:manager.openSettings()
  }
  Popup {
    id:picker;parent:manager.Window.window ? manager.Window.window.contentItem : manager
    anchors.centerIn:parent;width:Math.min(820,parent.width-24);height:Math.min(520,parent.height-24);modal:true
    padding:16;closePolicy:Popup.CloseOnEscape
    property var selected:skins.currentIndex>=0?manager.skinList[skins.currentIndex]:null
    ColumnLayout {
      anchors.fill:parent;spacing:8
      RowLayout {Layout.fillWidth:true;Label{text:"奶杀动皮 · 手动换皮";font.pixelSize:22;Layout.fillWidth:true}Button{text:"关闭";onClicked:picker.close()}}
      Label {Layout.fillWidth:true;wrapMode:Text.Wrap;text:manager.loaded?"资源包已启用。选择只作用于本机，不修改服务器皮肤。":"请先在「管理资源包」下载并启用「奶杀动皮」，再打开本页。"}
      RowLayout {
        Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:0;spacing:16
        Item {
          Layout.preferredWidth:Math.min(210,picker.width*.32);Layout.fillHeight:true;Layout.minimumHeight:0;clip:true
          Rectangle {anchors.fill:parent;color:"#283239";radius:8}
          Loader {id:previewLoader;objectName:"naishaPortraitPreview";anchors.centerIn:parent;width:Math.max(0,Math.min(190,parent.width,parent.height*120/180));height:width*180/120;active:picker.visible && !!picker.selected
            sourceComponent:NaishaPortrait{skin:picker.selected;resourceRoot:manager.resourceRoot}}
        }
        ScrollView {
          id:controlsScroll;objectName:"naishaControlsScroll"
          Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumWidth:0;Layout.minimumHeight:0;clip:true
          contentWidth:availableWidth
          ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
        ColumnLayout {
          width:controlsScroll.availableWidth;spacing:8
          ComboBox {id:skins;objectName:"naishaSkinChoice";Layout.fillWidth:true;model:manager.skinList;textRole:"title";onActivated:manager.updateTargets()}
          ComboBox {id:target;objectName:"naishaGeneralChoice";Layout.fillWidth:true;model:manager.targets;textRole:"label"}
          Label {Layout.fillWidth:true;wrapMode:Text.Wrap;text:manager.skinList.length?"选择当前武将后立即生效并保存。同一人物的其他版本可沿用；各版本也可单独选择或恢复。":"当前对局没有此包可适配的武将。"}
          Button {objectName:"naishaApplySkin";text:"使用并保存这款动皮";enabled:!!picker.selected && target.currentIndex>=0;onClicked:manager.choose(manager.targets[target.currentIndex].id,picker.selected)}
          Button {text:"此版本恢复原皮肤并保存";enabled:target.currentIndex>=0;onClicked:manager.choose(manager.targets[target.currentIndex].id,null)}
          Button {text:"预览攻击";enabled:!!picker.selected && !!picker.selected.attack;onClicked:preview("attack")}
          Button {text:"预览技能";enabled:!!picker.selected && !!picker.selected.skill;onClicked:preview("skill")}
          Label {Layout.fillWidth:true;wrapMode:Text.Wrap;color:"#d0644c";text:manager.error}
        }
        }
      }
    }
    function preview(action) {
      if(previewLoader.item)previewLoader.item.playAction(action);
    }
  }
}
