# SPDX-License-Identifier: GPL-3.0-or-later
"""Real stock AvatarChatBox plus the custom role picker; captures Chat packets locally."""
from pathlib import Path
import argparse,json,os,shutil,tempfile,time
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QObject,QUrl,QMetaObject,QPoint,Qt,Q_RETURN_ARG,qInstallMessageHandler,QEventLoop,QTimer,QEvent
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest,QSignalSpy
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,default=Path('runtime'));p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
R=Path(__file__).resolve().parents[1]/'runtime';logs=[]
qInstallMessageHandler(lambda kind,context,message:logs.append(message));app=QGuiApplication([])
font_file=Path('C:/Windows/Fonts/msyh.ttc')
if font_file.is_file():
 font_id=QFontDatabase.addApplicationFont(str(font_file));families=QFontDatabase.applicationFontFamilies(font_id)
 if families:app.setFont(QFont(families[0]))
temp=tempfile.TemporaryDirectory(dir=a.work_dir);B=Path(temp.name)
def put(name,text):
 f=B/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf-8')
put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Config','Lua','Backend','SkinBank','Cpp','Mediator']))
put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property var enabledResourcePacks:[];property bool replaying:false;property string libianName:"sans-serif";property string roomBg:"";property string lobbyBg:"";}')
put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject {
 property var captures:[]
 property var selfPlayer:({id:1,general:"self",deputyGeneral:""})
 property bool banned:false
 property bool large:false
 property bool emptyPool:false
 function tr(s){return s;}
 function ev(s){if(s.indexOf("FkCardCounterV2.remember")>=0){captures=captures.concat([s]);return true;}if(s.indexOf("Fk:canUseGeneral")===0)return !(banned && s.indexOf('"b"')>=0);
  if(s.indexOf("Fk:getAllGenerals")>=0){
   if(emptyPool)return ["silent","gap"].map(g=>({id:g,name:g,pack:"无语音包"}));
   if(large){const a=[];for(let i=0;i<1024;i++)a.push({id:"bulk"+i,name:"武将"+i,pack:"大将池"});return a;}
   return ["b","c","silent","death","win","zero","gap","pack"].filter(g=>!banned || g!=="b").map(g=>({id:g,name:({b:"有专属语音",c:"有通用技能语音",death:"仅阵亡语音",win:"仅胜利语音",zero:"仅无编号语音",silent:"无语音",gap:"缺首条编号",pack:"资源包专属"})[g],pack:"启用包"}));}return true;}

}''')
put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject {
 property int listings:0
 function exists(p){return !!p;}
 function readFileFromAssets(p){return "{}";}
 function writeFileToAssets(p,v){return true;}
 function ls(path){listings++;if(path.indexOf("/resource_pak/alt/")>=0)return path.endsWith("/skill/")?["pack_voice1.mp3"]:[];
 if(path.endsWith("/skill/"))return ["own_self1.mp3","skill_b_b1.mp3","skill_b1.mp3","normal1.mp3","zero.mp3","gap2.mp3"];
 if(path.endsWith("/death/"))return ["b.mp3","death.mp3"];
 if(path.endsWith("/win/"))return ["win.mp3"];return [];
 }
}''')
put('Fk/SkinBank.qml','''pragma Singleton
import QtQuick
QtObject {property int probes:0;function getAudioRealPath(name,extension,kind){probes++;
 if(kind==="skill" && ["own_self1","skill_b_b1","skill_b1","normal1","zero","gap2"].indexOf(name)>=0)return "mock/"+name;
 if(kind==="skill" && name==="pack_voice1" && Config.enabledResourcePacks.indexOf("alt")>=0)return "mock/pack_voice1";
 if(kind==="death" && ["b","death"].indexOf(name)>=0)return "mock/"+name+"_death";
 if(kind==="win" && name==="win")return "mock/win";
 return undefined;
}}''')
put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject {property string os:"Android";property string path:"/fixture";}')
put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject {signal commandGot(var sender,string command,var data)}')
put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
put('LunarLtk/Ltk.qml','''pragma Singleton
import QtQuick
QtObject {property var roomScene:null;property int metadataCalls:0;
 function getGeneralDetail(g){metadataCalls++;let name="normal";
 if(g==="self")name="own";else if(g==="b")name="skill_b";
 else if(["silent","death","win"].indexOf(g)>=0)name="missing";
 else if(["zero","gap"].indexOf(g)>=0)name=g;
 else if(g==="pack")name="pack_voice";
 else if(g.startsWith("bulk"))name=Number(g.slice(4))%2?"missing":"normal";
 return {gender:2,skill:[{name:name}]};}
 function getGeneralData(g){return {extension:"fixture"};}
 function getSkillData(s){return {extension:"fixture"};}
}''')
put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n')
shutil.copy2(R/'Fk/Widgets/TapHandler.qml',B/'Fk/Widgets/TapHandler.qml')
shutil.copy2(R/'Fk/Components/Common/AvatarChatBox.qml',B/'AvatarChatBox.qml')
shutil.copy2(R/'Fk/Components/GameCommon/BasicItem.qml',B/'BasicItem.qml')
put('Avatar.qml','import QtQuick\nItem {property string general;}')
put('MetroButton.qml','import QtQuick.Controls\nButton {}')
put('LogEdit.qml','import QtQuick\nListView {function append(a){}function clear(){}}')
put('CardItem.qml','import QtQuick\nItem {property bool known:false;property var dataModel;}')
shutil.copytree(a.payload/'card-counter',B/'card-counter')
put('Main.qml','''import QtQuick
import Fk
import LunarLtk
import "card-counter" as Counter
Window {
 id:win;width:1000;height:540;visible:true
 property var sent:[]
 property int longPresses:0
 property int initialChecks:-1
 property alias endpoint:client
 property alias selfObject:selfFixture
 QtObject {id:selfFixture;property int id:1}
 QtObject {id:client;function notifyServer(command,data){win.sent=win.sent.concat([{command:command,data:data}]);}}
 AvatarChatBox {id:chat;x:20;y:10;width:480;height:500}
 Counter.CounterHost {id:counter}
 Item {id:interactionScene;property var popupItem:null;function closeInfoPopup(){}}
 Item {id:reveal;visible:false
  CardItem {known:true;dataModel:({cardId:27})}
  CardItem {known:false;dataModel:({cardId:28})}
  Item {visible:false;CardItem {known:true;dataModel:({cardId:29})}}
  CardItem {known:true;dataModel:({cardId:-2})}
 }
 function revealCards(){reveal.visible=true;interactionScene.popupItem=reveal;}
 function capturedCards(){return JSON.stringify(Lua.captures);}
 function hideReveal(){reveal.visible=false;counter.rememberPopupCards();}
 BasicItem {id:targetPhoto;onRightClicked:win.longPresses++;x:800;y:200;width:100;height:130;selectable:false;property var dataModel:({playerid:2,screenName:"测试目标"})}
 function actionsState(){return JSON.stringify({signals:longPresses,scene:!!counter.currentScene,visible:targetPhoto.visible,x:targetPhoto.x,y:targetPhoto.y});}
 function prepareActions(){control().soundList.visible=false;control().children.find(b=>b.objectName==="roleVoiceButton");counter.currentScene=interactionScene;counter.attachPlayerActions(targetPhoto);}
 function egg(){return counter.sendPresent("Egg");}
 function flower(){return counter.sendPresent("Flower");}
 function replayMode(){Config.replaying=true;}

 function voice(){return chat.children[0].children[0];}
 function control(){const q=[chat];while(q.length){const n=q.pop();if(n.objectName==="roleVoiceControl")return n;if(n.children)q.push(...Array.from(n.children));}return null;}
 function buttonGeometry(){const c=control(),b=c.children.find(x=>x.objectName==="roleVoiceButton"),p=b.mapToItem(null,b.width/2,b.height/2);return JSON.stringify({parent:String(c.parent),width:b.width,height:b.height,labelWidth:b.contentItem.width,fontSize:b.font.pixelSize,x:p.x,y:p.y});}
 function pickerVisible(){return control().pickerVisible;}
 function setup(){counter.attachRoleVoices(chat);counter.attachRoleVoices(chat);}
 function pickB(){control().refreshPool();control().choose("b");}
 function doubleGeneral(){Lua.selfPlayer={id:1,general:"self",deputyGeneral:"b"};control().rebuildVoices();}
 function restoreGeneral(){Lua.selfPlayer={id:1,general:"self",deputyGeneral:""};control().rebuildVoices();}
 function sameRoomSettings(){Mediator.commandGot(null,"ChangeRoom",["same room",4,15,{}]);}
 function voiceLabels(){const c=control(),labels=[];for(let i=0;i<c.soundList.model.count;i++)labels.push(c.voiceText(c.soundList.model.get(i)));return JSON.stringify(labels);}
 function pickC(){control().choose("c");}
 function reopen(){control().soundList.visible=true;}
 function refresh(){control().rebuildVoices();}
 function ban(){Lua.banned=true;control().rebuildVoices();}
 function sendSpecific(){const list=control().soundList;for(let i=0;i<list.count;i++)if(list.model.get(i).name==="skill_b"){list.positionViewAtIndex(i,ListView.Contain);list.forceLayout();const item=list.itemAtIndex(i);if(!item)return false;item.clicked();return true;}return false;}
 function sendAgain(){return control().sendVoice({name:"skill_b",idx:1,specific:true,general:"b"});}
 function fast(){return control().sendVoice({name:"fastchat_m",idx:2,specific:false,general:""});}
 function reopenCatalog(){control().children.find(b=>b.objectName==="roleVoiceButton").clicked();}
 function selectSilent(){control().choose("silent");}
 function selectZero(){control().choose("zero");}
 function selectDeath(){control().choose("death");}
 function selectWin(){control().choose("win");}
 function selectPack(){control().choose("pack");}
 function selectGap(){control().choose("gap");}
 function resourcePack(){Config.enabledResourcePacks=["alt"];}
 function largeCatalog(){Lua.large=true;control().refreshPool(true);initialChecks=control().checkedCount;}
 function clearLarge(){Lua.large=false;control().refreshPool();}
 function catalogState(){const c=control();return JSON.stringify({pool:c.generals.map(g=>g.id),checked:c.checkedCount,total:c.candidates.length,scanning:c.scanning,initial:initialChecks,metadata:Ltk.metadataCalls,probes:SkinBank.probes,dirs:Backend.listings,selected:c.selectedGeneral});}
 function compactChat(){chat.scale=.6;}
 function changeRoom(){Mediator.commandGot(null,"EnterRoom",[]);control().refreshPool();}
 function rebuildControl(){const c=control(),row=c.parent;c.destroy();counter.adaptedControls=[];Qt.callLater(function(){counter.attachRoleVoices(chat);control().refreshPool();});}
 function silentCatalog(){Lua.large=false;Lua.emptyPool=true;control().refreshPool(true);}
 function snapshot(){const c=control();const rows=[];for(let i=0;i<c.soundList.model.count;i++)rows.push(c.soundList.model.get(i));return JSON.stringify({count:rows.length,rows:rows,selected:c.selectedGeneral,pool:c.generals,sent:sent,controls:counter.adaptedControls.filter(x=>x===chat).length});}
}''')
engine=QQmlApplicationEngine();engine.addImportPath(str(B))
# The stock box only touches these context objects when appending/sending.
engine.rootContext().setContextProperty('ClientInstance',None);engine.rootContext().setContextProperty('Self',None)
engine.rootContext().setContextProperty('AppPath',QUrl.fromLocalFile(str(B)))
engine.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
engine.rootContext().setContextProperty('ClientInstance',win.property('endpoint'));engine.rootContext().setContextProperty('Self',win.property('selfObject'))
def pump(t=.12):
 loop=QEventLoop();QTimer.singleShot(max(1,round(t*1000)),loop.quit);loop.exec()
 app.sendPostedEvents(None,QEvent.DeferredDelete)
def invoke(n):return QMetaObject.invokeMethod(win,n,Qt.DirectConnection,Q_RETURN_ARG('QVariant'))
def call(n):QMetaObject.invokeMethod(win,n,Qt.DirectConnection);pump()
call('setup')
geometry=json.loads(invoke('buttonGeometry'))
assert 'RowLayout' in geometry['parent'] and geometry['width']>=40 and geometry['height']>=30,geometry
assert geometry['labelWidth']>=2*geometry['fontSize'],'role label must fit inside themed button padding'
assert 20<=geometry['x']<=500 and 10<=geometry['y']<=510,geometry
QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(geometry['x']),round(geometry['y'])))
pump(.3);assert invoke('pickerVisible') is True,'visible role button must accept a real pointer click'
assert win.grabWindow().save(str(a.work_dir/'role-picker.png'))
call('pickB');pump(.3);initial=json.loads(invoke('snapshot'))
assert initial['controls']==1 and initial['selected']=='b',initial
assert [r['name'] for r in initial['rows']].count('skill_b')==1,initial
assert {r['id'] for r in initial['pool']}=={'b','c','death','win','zero'},initial['pool']
call('refresh');assert json.loads(invoke('snapshot'))['count']==initial['count'],'no duplicate voices'
call('doubleGeneral');dual=json.loads(invoke('snapshot'));labels=json.loads(invoke('voiceLabels'))
assert dual['selected']=='b' and [r['name'] for r in dual['rows']].count('skill_b')==1,dual
assert any(s.startswith('【b】') for s in labels) and any(s.startswith('【self】') for s in labels),labels
assert all(not s.startswith('【') for s in labels if s.startswith('fastchat')),labels
call('sameRoomSettings');assert json.loads(invoke('snapshot'))['selected']=='b','settings updates must preserve the selected voice'
call('restoreGeneral')
assert invoke('sendSpecific') is True;state=json.loads(invoke('snapshot'))
assert state['sent']==[{'command':'Chat','data':{'type':2,'msg':'$skill_b:1:b'}}],state
assert not invoke('sendAgain'),'cooldown prevents duplicate packet'
pump(1.55);call('reopen');call('ban');banned=json.loads(invoke('snapshot'))
assert banned['selected']=='' and not any(r['name']=='skill_b' for r in banned['rows']),banned
assert not invoke('sendAgain'),'disabled general cannot be sent'
call('pickC');generic=json.loads(invoke('snapshot'))
assert any(r['name']=='normal' and not r['specific'] for r in generic['rows']),generic
assert invoke('fast') is True
final=json.loads(invoke('snapshot'));assert final['sent'][-1]['data']['msg']=='$fastchat_f:2',final

# No-audio and unreachable numbered gaps never become selectable.
call('selectSilent');assert json.loads(invoke('snapshot'))['selected']=='c'
call('selectGap');assert json.loads(invoke('snapshot'))['selected']=='c'
call('selectZero');zero=json.loads(invoke('snapshot'))
assert any(r['name']=='zero' and r['idx']==0 for r in zero['rows']),zero
call('selectDeath');death=json.loads(invoke('snapshot'))
assert any(r['name']=='~death' for r in death['rows']),death
assert any(s.startswith('【death】') for s in json.loads(invoke('voiceLabels'))),'death voices identify their general'
call('selectWin');win_audio=json.loads(invoke('snapshot'))
assert any(r['name']=='!win' for r in win_audio['rows']),win_audio
# Specific audio wins even when a shared audio file also exists.
assert not any(r['name']=='skill_b' and not r['specific'] for r in initial['rows']),initial
# Warm reopen reuses both successful and missing probes; the resource pack
# change invalidates the index and exposes newly available downloaded voices.
before_cache=json.loads(invoke('catalogState'));call('reopenCatalog');pump(.3)
after_cache=json.loads(invoke('catalogState'))
assert before_cache['probes']==after_cache['probes'] and before_cache['dirs']==after_cache['dirs'],(before_cache,after_cache)
call('changeRoom');room_cache=json.loads(invoke('catalogState'))
assert not room_cache['scanning'] and room_cache['metadata']==after_cache['metadata'] and room_cache['dirs']==after_cache['dirs'],room_cache
call('rebuildControl');new_control=json.loads(invoke('catalogState'))
assert not new_control['scanning'] and new_control['metadata']==room_cache['metadata'] and new_control['probes']==room_cache['probes'],new_control
assert new_control['pool']==room_cache['pool'],new_control
geometry=json.loads(invoke('buttonGeometry'))

call('resourcePack');pump(.3);call('reopenCatalog');pump(.3)
assert 'pack' in json.loads(invoke('catalogState'))['pool'],(json.loads(invoke('catalogState')),logs)
call('selectPack');pack=json.loads(invoke('snapshot'));assert any(r['name']=='pack_voice' for r in pack['rows']),pack
# A large catalog begins asynchronously, yields to the event loop, and can be
# cancelled by closing the picker. No audio packet is sent by any selection.
pump(.3)
QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(geometry['x']),round(geometry['y'])));pump(.3)
assert invoke('pickerVisible') is True
QMetaObject.invokeMethod(win,'largeCatalog',Qt.DirectConnection)
catalog=win.findChild(QObject,'roleVoiceList');assert catalog
model=catalog.property('model');resets=QSignalSpy(model.modelReset)
large_start=json.loads(invoke('catalogState'));assert large_start['initial']==0 and large_start['checked']==0,large_start
pump(.05);large_partial=json.loads(invoke('catalogState'));assert 0<large_partial['checked']<1024,large_partial
picker=win.findChild(QObject,'roleVoicePicker');assert picker
assert 0<=picker.property('x') and 0<=picker.property('y')
assert picker.property('x')+picker.property('width')<=win.width() and picker.property('y')+picker.property('height')<=win.height()
QMetaObject.invokeMethod(picker,'close');pump(.1);paused=json.loads(invoke('catalogState'))
pump(.1);assert json.loads(invoke('catalogState'))['checked']==paused['checked'],'closed picker must do no scan work'
pump(.35)
QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(geometry['x']),round(geometry['y'])))
end=time.monotonic()+8
while json.loads(invoke('catalogState'))['scanning'] and time.monotonic()<end:pump(.02)
large_done=json.loads(invoke('catalogState'));assert large_done['checked']==1024 and len(large_done['pool'])==512,large_done
assert resets.count()==0,'incremental detection must not reset the list model'
assert large_done['dirs']<=after_cache['dirs']+20,'audio directories must be indexed, not re-read per general'
assert json.loads(invoke('snapshot'))['sent']==final['sent'],'browsing and choosing roles must not send chat'
# The picker remains on-screen even when the stock chat box is scaled.
call('compactChat');win.setWidth(568);win.setHeight(320);pump(.15)
assert picker.property('x')>=0 and picker.property('y')>=0
assert picker.property('x')+picker.property('width')<=568 and picker.property('y')+picker.property('height')<=320
call('silentCatalog');pump(.2);empty=json.loads(invoke('catalogState'));assert empty['pool']==[] and empty['scanning'] is False,empty

QMetaObject.invokeMethod(picker,'close');win.setWidth(1000);win.setHeight(540);call('prepareActions')
pump(.4)  # Let the prior modal picker's exit transition release pointer input.
QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,QPoint(850,250));pump(.95);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(850,250));pump(.1)
actions=win.findChild(QObject,'playerPresentActions');win.grabWindow().save(str(a.work_dir/'actions.png'));assert actions and actions.property('visible'),('long press opens interaction choices',invoke('actionsState'),logs)
before_present=json.loads(invoke('snapshot'))['sent'];assert before_present==final['sent'],'opening interaction choices sends nothing'
assert invoke('egg') is True
assert invoke('flower') is False,'gift cooldown prevents duplicate sends'
assert json.loads(invoke('snapshot'))['sent'][-1]=={'command':'Chat','data':{'type':2,'msg':'$@Egg:2'}}
host=win.findChild(QObject,'fkCounterHost')
cooldowns=[obj for obj in host.findChildren(QObject) if obj.property('interval')==1500]
assert len(cooldowns)==1,'the present rate limit must have one timer'
cooldown=cooldowns[0];assert cooldown.property('running') is True
cooldown_deadline=time.monotonic()+3
while cooldown.property('running') and time.monotonic()<cooldown_deadline:pump(.02)
assert cooldown.property('running') is False,'present rate limit did not expire'
assert invoke('flower') is True
assert json.loads(invoke('snapshot'))['sent'][-1]['data']['msg']=='$@Flower:2'
call('replayMode');assert invoke('egg') is False,'replays cannot send gifts'
call('revealCards');captured=json.loads(invoke('capturedCards'))
assert len(captured)==1 and 'remember({27})' in captured[0],captured
pump(.2);assert json.loads(invoke('capturedCards'))==captured,'reveals are captured once, without polling'
call('hideReveal');assert json.loads(invoke('capturedCards'))==captured,'hidden popups are not captured'

errors=[m for m in logs if any(x in m for x in ['TypeError','ReferenceError','SyntaxError','Unable to assign','Cannot assign','Binding loop','is not a type'])]
print(json.dumps({'button_geometry':geometry,'initial':initial,'banned':banned,'final':final,'large':{'checked':large_done['checked'],'with_audio':len(large_done['pool']),'first_batch_checked':large_partial['checked'],'directories':large_done['dirs']},'errors':errors},ensure_ascii=False,indent=2));assert not errors,errors
win.close();engine.deleteLater();app.processEvents()
