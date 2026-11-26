"""Real CounterHost routing: public actor identity, main/deputy, and no unrelated triggers."""
import argparse,json,os,shutil,tempfile,zipfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,QTimer,QEventLoop,qInstallMessageHandler,Qt,QPoint
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);p.add_argument('--light-pack',type=Path);p.add_argument('--tenyear-pack',type=Path);p.add_argument('--target-line-pack',type=Path);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
if os.name=='nt':
 font_id=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc')
 assert font_id>=0,'A CJK font is required for the known-card screenshot'
 app.setFont(QFont(QFontDatabase.applicationFontFamilies(font_id)[0]))
with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
 b=Path(tmp)
 def put(n,s):
  path=b/n;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend','Mediator','SkinBank','Fs']))
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"Android";property string path:'+json.dumps(b.as_uri())+';}')
 files=[]
 for archive in [pack for pack in [a.light_pack,a.tenyear_pack,a.target_line_pack] if pack]:
  with zipfile.ZipFile(archive) as bundle:
   for entry in bundle.namelist():
    if not entry.startswith('packages/freekill-core/image/') or '..' in Path(entry).parts or entry.endswith('/'):continue
    target=b/'resource_pak'/'test-light'/Path(entry).parent/Path(entry).name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(bundle.read(entry));files.append(target.as_uri())
 put('Fk/Fs.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool forceMissing:false;function exists(path){return !forceMissing&&'+json.dumps(files)+'.includes(path);}}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool banChangeSkin:false;property bool replaying:false;property bool observing:false;property bool consoleStartRequested:false;property string screenName:"saved-user";property string password:"saved-password";property var blockedUsers:[];property var enabledResourcePacks:[];}')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject{property var knownHands: [];function ev(s){if(s.includes("FkCardCounterV2.current"))return {knowledge:{hands:knownHands}};if(s.includes("hasTag"))return s.includes("fixture_combo");return s.includes("getSkillNameList")?(s.includes("fixture_skill")||s.includes("fixture_combo")):true;}function tr(s){return s;}}')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{property string functionPrefs:\'{"haptics":true,"future":7}\';property var missing:[];function exists(p){return !missing.includes(String(p))&&'+json.dumps(files)+'.includes(p);}function readFileFromAssets(p){return p==="function-settings.json"?functionPrefs:"{}";}function writeFileToAssets(p,v){if(p==="function-settings.json")functionPrefs=v;return true;}}')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data);function notify(sender,cmd,data){commandGot(sender,cmd,data);}}')
 put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject{}')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n');put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject{property var roomScene:null;}')
 put('LunarLtk/Pages/InfoPopups/qmldir','module LunarLtk.Pages.InfoPopups\nViewPile 1.0 ViewPile.qml\n');put('LunarLtk/Pages/InfoPopups/ViewPile.qml','import QtQuick\nItem{}')
 # Simulated native lifecycle only. Real Spine rendering has a separate C++ probe.
 put('Spine/qmldir','module Spine\nSkeletonAnimation 1.0 SkeletonAnimation.qml\nsingleton SpineVersion 1.0 SpineVersion.qml\nsingleton TestControl 1.0 TestControl.qml\n')
 put('Spine/SpineVersion.qml','pragma Singleton\nimport QtQuick\nQtObject{enum Version{Auto}}')
 put('Spine/TestControl.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool failLoad:false;property bool neverComplete:false;}')
 put('Spine/SkeletonAnimation.qml','''import QtQuick
Item{id:root;property url atlasFile;property url skeletonDataFile;property real skeletonScale:1;property real timeScale:1;property int spineVersion:0;property bool premultipliedAlapha:false;property bool loaded:false;property bool playing:false
 signal skeletonLoadFinished(bool ok);signal complete(int trackIndex,int loopCount)
 function clearTracks(){playing=false;clock.stop();}function setToSetupPose(){}
 function setAnimation(track,name,loop){playing=loaded&&name==="play";if(playing&&!loop&&!TestControl.neverComplete)clock.restart();}
 function isPlaying(track){return playing;}
 Timer{interval:15;running:true;onTriggered:{root.loaded=!TestControl.failLoad;root.skeletonLoadFinished(root.loaded);}}
 Timer{id:clock;interval:2333;onTriggered:{root.playing=false;root.complete(0,1);}}
}''')
 shutil.copytree(a.payload/'card-counter',b/'card-counter')
 put('HandcardViewer.qml','import QtQuick\nRectangle{width:25;height:80;color:"#ffaa44";property bool stockActive:true;visible:stockActive}')
 put('SettingsFixture.qml','''import QtQuick
import QtQuick.Controls
Item {
 width:800;height:500
 Item { property var model: ListModel { ListElement{name: "Userinfo Settings"} ListElement{name: "BG Settings"} ListElement{name:"Audio Settings"} ListElement{name:"Control Settings"} ListElement{name:"UI settings"} } }
 SwipeView { Item{} Item{} Item{} Item{} Item{} }
}''')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import Spine
import "card-counter" as Counter
Window{id:win;width:800;height:500;visible:true;property var actions:[];property int tableClicks:0;property int layerClicks:0;property var viewedIds:[];property int viewCalls:0
 Counter.CounterHost{id:counter}
 Item{id:navigation;anchors.fill:parent;z:30000;visible:false
  property bool busy:false;property var callbacks:({});property int updates:0;property int localStarts:0
  function addCallback(name,callback){callbacks[name]=callback;}
  function tryUpdatePackage(){updates++;}
  StackView{id:navStack;anchors.fill:parent}
 }
 Component{id:homeComponent;Item{
  property alias serverDialog:panelLoader
  Button{x:20;y:20;width:150;height:50;text:"Console start";onClicked:navigation.localStarts++}
  Item{id:panel;anchors.fill:parent;visible:true
   function hide(){visible=false;}
   Loader{id:panelLoader}
   MouseArea{anchors.fill:parent}
  }
 }}
 Component{id:onlineComponent;Item{}}
 function homeAttach(){counter.clientContext=null;navigation.visible=true;navStack.push(homeComponent,StackView.Immediate);counter.navigationRoot=navigation;}
 function homeConnect(){counter.clientContext=({online:true});const h=navStack.get(0);h.serverDialog.parent.visible=true;navStack.push(onlineComponent,StackView.Immediate);navStack.push(onlineComponent,StackView.Immediate);navigation.busy=true;}
 function homeReturnConnected(){navigation.callbacks.BackToStart(null,{preserveSession:true});}
 function homeDisconnectFirst(){counter.clientContext=null;}
 function homeReturnDuringPush(){counter.clientContext=null;navStack.push(onlineComponent);navigation.callbacks.BackToStart(null,{});}
 function homeReturn(){navigation.callbacks.BackToStart(null,{});}
 function homeState(){const h=navStack.get(0);return JSON.stringify({depth:navStack.depth,enabled:h.enabled,panel:h.serverDialog.parent.visible,busy:navigation.busy,online:!!counter.clientContext,updates:navigation.updates,starts:navigation.localStarts,username:Config.screenName,password:Config.password});}
 QtObject{id:actor;property int playerid:2;property string general:"guanning";property string deputyGeneral:"ganning";property var photoItem:photo}
 Item{id:scene;anchors.fill:parent;property var dataModel:({players:[actor]});property var popupItem:null;property var agItem:null;property alias infoPopup:info;property alias roomArea:playfield
  function getPhoto(id){return id===2?photo:id===3?otherPhoto:null;}
  function showInfoPopup(component,params){win.viewedIds=params.ids;win.viewCalls++;}
  function getPhotoOrDashboard(id){return id===2?wideDashboard:getPhoto(id);}
  Item{id:wideDashboard;x:0;y:300;width:800;height:200}
  Item{id:otherPhoto;x:620;y:40;width:80;height:100}
  Item{id:playfield;anchors.fill:parent}
  Rectangle{id:cover;anchors.fill:parent;z:8100;color:"#d02020";visible:false}
  Item{id:toolbar;x:100;y:180;property real stockDepth:3;z:stockDepth
   Button {width:120;height:50;text:"Skill";background:Rectangle{color:"#184fb5"} onClicked:win.layerClicks++}
  }
  Item{id:customToolbar;x:250;y:180;z:4
   Item{width:120;height:50;property string text:"Metro button";signal clicked();onClicked:win.layerClicks++
    Rectangle{anchors.fill:parent;color:"#10a050"} MouseArea{anchors.fill:parent;onClicked:parent.clicked()}
   }
  }
  Rectangle{id:layerDialog;x:90;y:170;width:300;height:80;z:1000;color:"#202830";visible:false}
  Item{id:info;visible:false;property var item:null}
  Button{x:600;y:440;width:150;height:40;text:"Table control";onClicked:win.tableClicks++}
  Item{id:photo;x:300;y:120;width:120;height:145;property string general:actor.general;property string deputyGeneral:actor.deputyGeneral;property var playSkinAction:null
   HandcardViewer{id:stock}
   Item{property string general:photo.general;function playAction(a){win.actions=win.actions.concat(["main:"+a]);return true;}}
   Item{property string general:photo.deputyGeneral;function playAction(a){win.actions=win.actions.concat(["deputy:"+a]);return true;}}
  }
 }
 property var fixtureSettings: null
 function settingsAttach(){fixtureSettings=Qt.createComponent("SettingsFixture.qml").createObject(win.contentItem);counter.adaptFunctionSettings(fixtureSettings);counter.adaptFunctionSettings(fixtureSettings);}
 function settingsDisable(){counter.setDirectionalLuckEnabled(false);counter.handleLuckCommand("AskForSkillInvoke",["AskForLuckCard",""]);}
 function featurePrefs(){return Backend.functionPrefs;}
 function settingsState(){const bar=fixtureSettings.children.find(c=>"model" in c);const pages=fixtureSettings.children.find(c=>"addItem" in c);return JSON.stringify({tabs:bar.model.count,pages:pages.count,enabled:counter.directionalLuckEnabled,panel:!!counter.luckPanel});}
 function attach(){counter.currentScene=scene;}
 function layerShow(){cover.visible=true;}
 function layerDialogShow(){layerDialog.visible=true;scene.popupItem=layerDialog;}
 function layerDialogHide(){layerDialog.visible=false;scene.popupItem=null;}
 function layerRestoreProbe(){toolbar.stockDepth=12;}
 function layerReset(){cover.visible=false;toolbar.stockDepth=3;}
 function layerState(){return JSON.stringify({toolbar:toolbar.z,custom:customToolbar.z,playfield:playfield.z,dialog:layerDialog.z,x:toolbar.x,y:toolbar.y,sameParent:toolbar.parent===scene});}
 function attack(){Mediator.commandGot(null,"Fk.GuanNingSkinAction",{player:2,action:"attack"});}
 function skill(){Mediator.commandGot(null,"Animate",{type:"InvokeSkill",player:2,name:"fixture_skill"});}
 function unrelated(){for(const c of ["AskForUseCard","MoveFocus","GameLog","CancelRequest"])Mediator.commandGot(null,c,{player:2,action:"attack"});Mediator.commandGot(null,"Animate",{type:"Indicate",player:2});Mediator.commandGot(null,"Fk.GuanNingSkinAction",{player:3,action:"attack"});}
 function alias(){actor.general="delight__guanning";}
 function deputy(){actor.general="ganning";actor.deputyGeneral="wyfx__guanning";}
 function ultMain(){Mediator.commandGot(null,"Animate",{type:"InvokeUltSkill",player:2,name:"fixture_skill",deputy:false});}
 function ultDeputy(){Mediator.commandGot(null,"Animate",{type:"InvokeUltSkill",player:2,name:"fixture_skill",deputy:true});}
 function unrelatedDeputySkill(){Mediator.commandGot(null,"Animate",{type:"InvokeSkill",player:2,name:"other_general_skill"});}
 function noSkin(){Config.banChangeSkin=true;}
 function hidden(){Config.banChangeSkin=false;photo.visible=false;}
 function restore(){photo.visible=true;}
 function useNative(){photo.playSkinAction=function(a,g){win.actions=win.actions.concat(["native:"+a+":"+g]);return true;};}
 function leave(){counter.currentScene=null;}
 function configureLight(main, deputy, enabled) { actor.general=main; actor.deputyGeneral=deputy; Config.enabledResourcePacks=enabled ? ["test-light"] : []; }
 function combo(){Mediator.commandGot(null,"Animate",{type:"InvokeSkill",player:2,name:"fixture_combo"});}
 function comboDeputy(){Mediator.commandGot(null,"Animate",{type:"InvokeUltSkill",player:2,name:"fixture_combo",deputy:true});}
 function comboWith(name){Mediator.commandGot(null,"Animate",{type:"InvokeSkill",player:2,name:name});}
 function comboFail(value){TestControl.failLoad=value;}
 function comboNeverComplete(value){TestControl.neverComplete=value;}
 function comboPending(){return counter.tenyearComboQueue.length;}
 function legacyMissingCache(){Fs.forceMissing=true;}
 function targetArtwork(){return counter.targetLineArtwork();}
 function targetMissingOL(){const png=counter.lightEffectImage("ol-target-line/zhixiangxianlong");Backend.missing=[String(png).slice(0,-4)+".skel"];}
 function targetMissingAll(){Backend.missing=Backend.missing.concat([counter.lightEffectImage("gold-head-frames"),counter.lightEffectImage("gold-trail")]);}
 function targetRestore(){Backend.missing=[];}
 function targetCreate(){counter.showLightTargetLine(scene,2,[2,3,99],counter.targetLineArtwork());}
 function targetGeometry(){return JSON.stringify(scene.children.filter(c=>c.objectName==="lightTargetLine").map(c=>({from:[c.origin.x,c.origin.y],to:[c.destination.x,c.destination.y],ol:c.olOriginalFrames})));}
 function comboState(){return JSON.stringify(scene.children.filter(c=>c.objectName==="fkTenyearCombo"&&c.visible).map(c=>({general:c.general,skill:c.skillName,width:c.width,started:c.started,base:String(c.resourceBase).split("/").pop()})));}
 function lightState(){return JSON.stringify(photo.children.filter(c=>"artwork" in c).map(c=>({asset:String(c.artwork).split("/").pop(),skill:c.skill,width:c.width,imageStatus:c.children[0].status})));}
 function knownHandRows(rows){Lua.knownHands=rows;counter.syncKnownHandBadges();}
 function knownHandOpen(){const b=scene.children.find(c=>c.objectName==="knownHandBadge"&&c.photo===photo);counter.openKnownHands(b.knownIds);}
 function knownHandExpire(){Lua.knownHands=[];}
 function knownHandLeftEdge(){photo.x=0;counter.syncKnownHandBadges();}
 function knownHandState(){const b=scene.children.find(c=>c.objectName==="knownHandBadge"&&c.photo===photo);const f=b&&b.children.find(c=>"contentHeight" in c);return JSON.stringify(b?{cards:b.knownCards,ids:b.knownIds,stockVisible:stock.visible,visible:b.visible,right:b.rightSide,width:b.width,height:b.height,x:b.x,y:b.y,flick:f.interactive,tableParent:b.parent===scene}:null);}
 function knownHandClipPortrait(){photo.clip=true;}
 function knownHandRemoveOwner(){scene.dataModel=({players:[]});counter.syncKnownHandBadges();}
 function knownHandRestoreOwner(){scene.dataModel=({players:[actor]});}
 function knownHandRelease(){counter.releaseScene();}
 function state(){return JSON.stringify(win.actions);}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.rootContext().setContextProperty('ClientInstance',app);engine.rootContext().setContextProperty('Self',None)
 engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump(ms=80):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def call(n):QMetaObject.invokeMethod(win,n);pump()
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 pump();call('attach');call('layerShow')
 def layerState():return json.loads(QMetaObject.invokeMethod(win,'layerState',Q_RETURN_ARG('QVariant')))
 layer=layerState();assert layer['toolbar']==3 and layer['custom']==4 and layer['playfield']==0 and layer['sameParent'] and layer['x']==100 and layer['y']==180,layer
 screen=win.grabWindow();assert screen.pixelColor(110,190).name()=='#d02020';assert screen.pixelColor(260,190).name()=='#d02020'
 QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(160,205));QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(310,205));pump();assert win.property('layerClicks')==2
 call('layerDialogShow');assert layerState()['dialog']==1000;assert win.grabWindow().pixelColor(110,190).name()=='#d02020'
 call('layerDialogHide');call('leave');call('layerRestoreProbe');assert layerState()['toolbar']==12 and layerState()['custom']==4,layerState()
 call('layerReset');call('attach');call('attack');call('skill');assert state()==['main:attack','main:skill'],(state(),logs)
 call('unrelated');assert len(state())==2,state()
 call('unrelatedDeputySkill');assert len(state())==2,state()
 call('alias');call('attack');assert state()[-1]=='main:attack',state()
 call('deputy');call('attack');assert state()[-1]=='deputy:attack',state()
 before=len(state());call('ultMain');assert len(state())==before,state();call('ultDeputy');assert state()[-1]=='deputy:skill',state()
 before=len(state());call('noSkin');call('attack');call('hidden');call('skill');assert len(state())==before,state()
 call('restore');call('useNative');call('attack');assert len(state())==before+1 and state()[-1]=='native:attack:wyfx__guanning',state()
 before=len(state());call('leave');call('attack');assert len(state())==before,state()
 combo_tested=False
 if a.light_pack:
  from PySide6.QtCore import Q_ARG
  def configure(main,deputy='',enabled=True):
   QMetaObject.invokeMethod(win,'configureLight',Q_ARG('QVariant',main),Q_ARG('QVariant',deputy),Q_ARG('QVariant',enabled));pump()
  def light(): return json.loads(QMetaObject.invokeMethod(win,'lightState',Q_RETURN_ARG('QVariant')))
  call('attach')
  # The old pack's polygon placeholders must no longer trigger on any ordinary
  # card use or on normal versions sharing the same base name.
  for main,deputy in [('jiangwei',''),('ganning','os__godmachao'),('ol__weiyan',''),('zhouyu','')]:
   configure(main,deputy);call('unrelated');call('attack');call('skill');assert light()==[],(main,light(),logs)
  configure('zhouyu',enabled=False);call('attack');assert light()==[],light()
  if a.tenyear_pack:
   def combo():return json.loads(QMetaObject.invokeMethod(win,'comboState',Q_RETURN_ARG('QVariant')))
   def pending():return QMetaObject.invokeMethod(win,'comboPending',Q_RETURN_ARG('QVariant'))
   configure('ty_wei__zhangliao');call('skill');call('attack');assert combo()==[],combo()
   call('comboDeputy');assert combo()==[],combo()
   call('legacyMissingCache')
   for general in ['zhangliao','lvbu','machao','mateng']:
    configure('ty_wei__'+general)
    call('combo');assert combo()==[{'general':'ty_wei__'+general,'skill':'fixture_combo','width':800,'started':True,'base':'wei'+general+'_jineng'}],(combo(),logs)
    call('combo');assert len(combo())==1 and pending()==0,(combo(),pending())
    if general=='zhangliao':
     QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(675,460));pump();assert win.property('tableClicks')==1,'Combo intercepted table controls'
    pump(2420);assert combo()==[],combo()
   configure('ganning','ty_wei__mateng');call('comboDeputy');assert len(combo())==1 and combo()[0]['general']=='ty_wei__mateng',combo();pump(2420);assert combo()==[],combo()
   configure('ty_wei__zhangliao',enabled=False);call('combo');assert combo()==[],combo()
   configure('zhouyu');call('combo');assert combo()==[],combo()
   configure('ty_wei__missing');call('combo');assert combo()==[],combo()
   configure('ty_wei__zhangliao');call('combo');QMetaObject.invokeMethod(win,'comboWith',Q_ARG('QVariant','fixture_combo_next'));pump();assert pending()==1,pending()
   pump(2420);assert len(combo())==1 and combo()[0]['skill']=='fixture_combo_next' and pending()==0,(combo(),pending())
   pump(2420);assert combo()==[],combo()
   configure('ty_wei__zhangliao');call('combo')
   for i in range(6):QMetaObject.invokeMethod(win,'comboWith',Q_ARG('QVariant','fixture_combo'+str(i)))
   pump();assert len(combo())==1 and pending()==4,(combo(),pending())
   configure('ty_wei__zhangliao',enabled=False);assert combo()==[] and pending()==0,(combo(),pending())
   configure('ty_wei__zhangliao');QMetaObject.invokeMethod(win,'comboFail',Q_ARG('QVariant',True));call('combo');pump();assert combo()==[] and pending()==0,(combo(),logs)
   QMetaObject.invokeMethod(win,'comboFail',Q_ARG('QVariant',False))
   configure('ty_wei__zhangliao');QMetaObject.invokeMethod(win,'comboNeverComplete',Q_ARG('QVariant',True));call('combo');assert len(combo())==1,combo();pump(4500);assert combo()==[],(combo(),logs)
   QMetaObject.invokeMethod(win,'comboNeverComplete',Q_ARG('QVariant',False))
   pump(270);call('combo');assert len(combo())==1,combo();call('leave');assert combo()==[] and pending()==0,(combo(),pending());call('attach')
   combo_tested=True
 from PySide6.QtCore import Q_ARG
 if a.target_line_pack:
  configure('zhouyu',enabled=True)
  def target():return QMetaObject.invokeMethod(win,'targetArtwork',Q_RETURN_ARG('QVariant'))
  assert target().endswith('/ol-target-line/zhixiangxianlong.png'),target()
  call('targetCreate')
  geometry=json.loads(QMetaObject.invokeMethod(win,'targetGeometry',Q_RETURN_ARG('QVariant')))
  assert geometry==[{'from':[360,192.5],'to':[660,90],'ol':True}],geometry
  call('targetMissingOL')
  if any(url.endswith('/gold-head-frames.png') for url in files):assert target().endswith('/gold-head-frames.png'),target()
  else:assert target()=='',target()
  call('targetMissingAll');assert target()=='',target()
  call('targetRestore');assert '/ol-target-line/' in target(),target()
  configure('zhouyu',enabled=False);assert target()=='',target()
 call('attach')
 def knowledge(rows):
  QMetaObject.invokeMethod(win,'knownHandRows',Q_ARG('QVariant',rows));pump()
 def badge():return json.loads(QMetaObject.invokeMethod(win,'knownHandState',Q_RETURN_ARG('QVariant')))
 knowledge([]);empty_badge_frame=win.grabWindow()
 knowledge([{'ownerId':2,'id':i+1,'name':name} for i,name in enumerate(['杀','杀','引蜂','酒'])]+[{'ownerId':2,'id':5,'name':'隐藏牌','uncertain':True},{'ownerId':3,'id':6,'name':'桃'}])
 assert badge()['cards']==['杀','杀','引蜂','酒'] and badge()['visible'] and not badge()['right'],(badge(),logs)
 assert not badge()['stockVisible'],'Duplicate native hand viewer left visible'
 assert 0<=badge()['x']<300 and badge()['height']<=145 and not badge()['flick'] and badge()['tableParent'],badge()
 call('knownHandClipPortrait')
 visible_badge=win.grabWindow();rect=(round(badge()['x'])+4,round(badge()['y'])+4,round(badge()['width'])-8,round(badge()['height'])-8)
 assert visible_badge.copy(*rect)!=empty_badge_frame.copy(*rect),'The table-side names must render even when the portrait clips children'
 pump(800);assert win.grabWindow().save(str(a.work_dir/'known-hand-four-cards.png'))
 QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(badge()['x']+badge()['width']/2),round(badge()['y']+badge()['height']/2)));pump()
 assert win.property('viewCalls')==1 and win.property('viewedIds').toVariant()==[1,2,3,4],(win.property('viewedIds').toVariant(),logs)
 call('knownHandExpire');call('knownHandOpen');assert win.property('viewCalls')==1, 'Expired cards reopened'
 call('knownHandLeftEdge');assert badge()['right'] and badge()['x']>=120,(badge(),logs)
 knowledge([{'ownerId':2,'name':'无懈可击'} for _ in range(20)])
 assert len(badge()['cards'])==20 and badge()['height']<=145,badge()
 knowledge([{'ownerId':2,'name':'过期记录','uncertain':True}]);assert not badge()['visible'] and badge()['cards']==[],badge()
 knowledge([]);assert not badge()['visible'] and badge()['stockVisible'],badge()
 call('knownHandRemoveOwner');assert badge() is None,'Stale photo-side rows must be destroyed'
 call('knownHandRestoreOwner');knowledge([{'ownerId':2,'name':'杀'}]);assert badge()['visible']
 call('knownHandRelease');assert badge() is None,'Leaving the room must remove table-parented rows'
 call('attach')
 call('settingsAttach');call('settingsDisable')
 settings=json.loads(QMetaObject.invokeMethod(win,'settingsState',Q_RETURN_ARG('QVariant')))
 assert settings=={'tabs':6,'pages':6,'enabled':False,'panel':False},(settings,logs)
 prefs=json.loads(QMetaObject.invokeMethod(win,'featurePrefs',Q_RETURN_ARG('QVariant')));assert prefs=={'haptics':True,'future':7,'directionalLuck':False},prefs
 call('homeAttach')
 def home():return json.loads(QMetaObject.invokeMethod(win,'homeState',Q_RETURN_ARG('QVariant')))
 for iteration in range(3):
  call('homeConnect');call('homeReturnConnected');assert home()['online'] and home()['panel'],home()
  call('homeConnect')
  if iteration%2:call('homeReturn');call('homeDisconnectFirst')
  else:call('homeDisconnectFirst');call('homeReturn')
  h=home();assert h['depth']==1 and h['enabled'] and not h['panel'] and not h['busy'] and not h['online'],h
  assert h['username']=='saved-user' and h['password']=='saved-password',h
  QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(90,45));pump()
 assert home()['starts']==3,home()
 call('homeReturnDuringPush');pump(600);assert home()['depth']==1 and not home()['panel'] and not home()['busy'],home()
 errors=[m for m in logs if any(t in m for t in ['TypeError','ReferenceError','SyntaxError','Cannot assign','Unable to assign'])];assert not errors,errors
 result={'passed':True,'publicAttackAndSkillRouting':True,'aliasesAndDeputy':True,'unrelatedRequestsIgnored':True,'nativeApiNoDuplicate':True,'hiddenAndDisabledBlocked':True,'obsoletePlaceholderBurstsExcluded':bool(a.light_pack),'originalComboRoutingAndSimulatedLifecycleTested':combo_tested,'knownHandNamesUncertaintyAndLayoutTested':True,'knownCardPopupAndStaleExclusion':True,'functionSettingsAndDisabledPopupTested':True,'controlsKeptAtOriginalDepth':True,'standardAndMetroControlsClickableUnderEffect':True,'animationAboveRoomDialog':True,'geometryAndParentUnchanged':True,'originalZBindingsUnchangedOnLeave':True,'repeatedHomeResetAndPreservedCredentials':True,'qt':__import__('PySide6').__version__}
 result['olTargetLineSelectionPartialDownloadFallbackAndDisableTested']=bool(a.target_line_pack)
 (a.work_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(result));win.close()
