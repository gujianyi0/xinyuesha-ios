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
  readonly property var scene:owner.currentScene
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
      let exists=false;
      try{exists=Lua.ev('Fk.generals['+JSON.stringify(general)+'] ~= nil')===true;}catch(_){}
      if (!exists) {error="客户端没有此武将 ID，请使用当前扩展的实际 ID";return false;}
      const translated=String(Lua.tr(general)).replace(/<[^>]*>/g,"");
      if (translated!==skin.character && general!==skin.sourceGeneral) {
        error="名称不一致："+translated+" / "+skin.character+"，未替换";return false;
      }
    }
    const next=Object.assign({},choices);
    if(skin)next[general]=skin.id;else delete next[general];
    if (!Backend.writeFileToAssets("naisha-skins.json",JSON.stringify(next))) {error="保存失败，未更改选择";return false;}
    choices=next;error="";release();sync();return true;
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
        const skin=catalog.find(s=>s.id===choices[general]);if(!skin)continue;
        const area=findArea(photo,general);if(!area)continue;
        let state=states.find(s=>s.area===area && s.skin===skin.id);
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
  onSceneChanged:{release();Qt.callLater(manager.sync);}
  Component.onCompleted:{readChoices();Qt.callLater(manager.reload);}
  Component.onDestruction:release()
  Timer {interval:800;repeat:true;running:manager.loaded && !!manager.scene && Object.keys(manager.choices).length>0;onTriggered:manager.sync()}
  function openSettings(){reload();picker.open();}
  Popup {
    id:picker;parent:manager.Window.window ? manager.Window.window.contentItem : manager
    anchors.centerIn:parent;width:Math.min(820,parent.width-24);height:Math.min(520,parent.height-24);modal:true
    padding:16;closePolicy:Popup.CloseOnEscape
    property var selected:skins.currentIndex>=0?manager.catalog[skins.currentIndex]:null
    ColumnLayout {
      anchors.fill:parent;spacing:8
      RowLayout {Layout.fillWidth:true;Label{text:"奶杀动皮（本地选择）";font.pixelSize:22;Layout.fillWidth:true}Button{text:"关闭";onClicked:picker.close()}}
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
          ComboBox {id:skins;Layout.fillWidth:true;model:manager.catalog;textRole:"title";onActivated:target.text=picker.selected.sourceGeneral}
          TextField{id:target;Layout.fillWidth:true;placeholderText:"目标武将 ID，例如 diaochan";text:picker.selected?picker.selected.sourceGeneral:""}
          Label {Layout.fillWidth:true;wrapMode:Text.Wrap;text:"不同扩展需填该扩展的武将 ID；核对名称后才会使用。停用资源包会恢复原皮肤。"}
          Button {text:"使用这款动皮";enabled:!!picker.selected;onClicked:manager.choose(target.text,picker.selected)}
          Button {text:"此武将恢复原皮肤";onClicked:manager.choose(target.text,null)}
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
