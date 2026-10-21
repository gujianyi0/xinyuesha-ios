# SPDX-License-Identifier: GPL-3.0-or-later
"""Real stock AvatarChatBox plus the custom role picker; captures Chat packets locally."""
from pathlib import Path
import argparse,json,os,shutil,tempfile,time
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QUrl,QMetaObject,QPoint,Qt,Q_RETURN_ARG,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,default=Path('runtime'));p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
R=Path(__file__).resolve().parents[1]/'runtime';logs=[]
qInstallMessageHandler(lambda kind,context,message:logs.append(message));app=QGuiApplication([])
temp=tempfile.TemporaryDirectory(dir=a.work_dir);B=Path(temp.name)
def put(name,text):
 f=B/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf-8')
put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Config','Lua','Backend','SkinBank','Cpp','Mediator']))
put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool replaying:false;property string libianName:"sans-serif";property string roomBg:"";property string lobbyBg:"";}')
put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject {
 property var selfPlayer:({id:1,general:"self",deputyGeneral:""})
 property bool banned:false
 function tr(s){return s;}
 function ev(s){if(s.indexOf("Fk:canUseGeneral")===0)return !banned && s.indexOf('"b"')>=0 || s.indexOf('"c"')>=0;
  if(s.indexOf("Fk:getAllGenerals")>=0)return banned?[{id:"c",name:"丙",pack:"启用包"}]:[{id:"b",name:"乙",pack:"启用包"},{id:"c",name:"丙",pack:"启用包"}];return true;}
}''')
put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject {function exists(p){return !!p;}function readFileFromAssets(p){return "{}";}function writeFileToAssets(p,v){return true;}}')
put('Fk/SkinBank.qml','''pragma Singleton
import QtQuick
QtObject {function getAudioRealPath(name,extension,kind){
 if(kind==="skill" && ["own_self1","skill_b_b1","normal1"].indexOf(name)>=0)return "mock/"+name;
 if(kind==="death" && name==="b")return "mock/b_death";
 return undefined;
}}''')
put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject {property string os:"Android";}')
put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject {signal commandGot(var sender,string command,var data)}')
put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
put('LunarLtk/Ltk.qml','''pragma Singleton
import QtQuick
QtObject {property var roomScene:null;
 function getGeneralDetail(g){return {gender:2,skill:[{name:g==="self"?"own":g==="b"?"skill_b":"normal"}]};}
 function getGeneralData(g){return {extension:"fixture"};}
 function getSkillData(s){return {extension:"fixture"};}
}''')
put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n')
shutil.copy2(R/'Fk/Widgets/TapHandler.qml',B/'Fk/Widgets/TapHandler.qml')
shutil.copy2(R/'Fk/Components/Common/AvatarChatBox.qml',B/'AvatarChatBox.qml')
put('Avatar.qml','import QtQuick\nItem {property string general;}')
put('MetroButton.qml','import QtQuick.Controls\nButton {}')
put('LogEdit.qml','import QtQuick\nListView {function append(a){}function clear(){}}')
shutil.copytree(a.payload/'card-counter',B/'card-counter')
put('Main.qml','''import QtQuick
import Fk
import "card-counter" as Counter
Window {
 id:win;width:1000;height:540;visible:true
 property var sent:[]
 property alias endpoint:client
 property alias selfObject:selfFixture
 QtObject {id:selfFixture;property int id:1}
 QtObject {id:client;function notifyServer(command,data){win.sent=win.sent.concat([{command:command,data:data}]);}}
 AvatarChatBox {id:chat;x:20;y:10;width:480;height:500}
 Counter.CounterHost {id:counter}
 function voice(){return chat.children[0].children[0];}
 function control(){const q=[chat];while(q.length){const n=q.pop();if(n.objectName==="roleVoiceControl")return n;if(n.children)q.push(...Array.from(n.children));}return null;}
 function buttonGeometry(){const c=control(),b=c.children.find(x=>x.objectName==="roleVoiceButton"),p=b.mapToItem(null,b.width/2,b.height/2);return JSON.stringify({parent:String(c.parent),width:b.width,height:b.height,labelWidth:b.contentItem.width,fontSize:b.font.pixelSize,x:p.x,y:p.y});}
 function pickerVisible(){return control().pickerVisible;}
 function setup(){counter.attachRoleVoices(chat);counter.attachRoleVoices(chat);}
 function pickB(){control().refreshPool();control().choose("b");}
 function pickC(){control().choose("c");}
 function reopen(){control().soundList.visible=true;}
 function refresh(){control().rebuildVoices();}
 function ban(){Lua.banned=true;control().rebuildVoices();}
 function sendSpecific(){const list=control().soundList;for(let i=0;i<list.count;i++)if(list.model.get(i).name==="skill_b"){list.positionViewAtIndex(i,ListView.Contain);list.forceLayout();const item=list.itemAtIndex(i);if(!item)return false;item.clicked();return true;}return false;}
 function sendAgain(){return control().sendVoice({name:"skill_b",idx:1,specific:true,general:"b"});}
 function fast(){return control().sendVoice({name:"fastchat_m",idx:2,specific:false,general:""});}
 function snapshot(){const c=control();const rows=[];for(let i=0;i<c.soundList.model.count;i++)rows.push(c.soundList.model.get(i));return JSON.stringify({count:rows.length,rows:rows,selected:c.selectedGeneral,pool:c.generals,sent:sent,controls:counter.adaptedControls.filter(x=>x===chat).length});}
}''')
engine=QQmlApplicationEngine();engine.addImportPath(str(B))
# The stock box only touches these context objects when appending/sending.
engine.rootContext().setContextProperty('ClientInstance',None);engine.rootContext().setContextProperty('Self',None)
engine.rootContext().setContextProperty('AppPath',QUrl.fromLocalFile(str(B)))
engine.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
engine.rootContext().setContextProperty('ClientInstance',win.property('endpoint'));engine.rootContext().setContextProperty('Self',win.property('selfObject'))
def pump(t=.12):
 end=time.monotonic()+t
 while time.monotonic()<end:app.processEvents();time.sleep(.003)
def invoke(n):return QMetaObject.invokeMethod(win,n,Qt.DirectConnection,Q_RETURN_ARG('QVariant'))
def call(n):QMetaObject.invokeMethod(win,n,Qt.DirectConnection);pump()
call('setup')
geometry=json.loads(invoke('buttonGeometry'))
assert 'RowLayout' in geometry['parent'] and geometry['width']>=40 and geometry['height']>=30,geometry
assert geometry['labelWidth']>=2*geometry['fontSize'],'role label must fit inside themed button padding'
assert 20<=geometry['x']<=500 and 10<=geometry['y']<=510,geometry
QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(geometry['x']),round(geometry['y'])))
pump(.3);assert invoke('pickerVisible') is True,'visible role button must accept a real pointer click'
call('pickB');pump(.3);initial=json.loads(invoke('snapshot'))
assert initial['controls']==1 and initial['selected']=='b',initial
assert [r['name'] for r in initial['rows']].count('skill_b')==1,initial
assert all(r['id'] in ['b','c'] for r in initial['pool'])
call('refresh');assert json.loads(invoke('snapshot'))['count']==initial['count'],'no duplicate voices'
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
errors=[m for m in logs if any(x in m for x in ['TypeError','ReferenceError','SyntaxError','Unable to assign','Cannot assign','Binding loop','is not a type'])]
print(json.dumps({'button_geometry':geometry,'initial':initial,'banned':banned,'final':final,'errors':errors},ensure_ascii=False,indent=2));assert not errors,errors
win.close();engine.deleteLater();app.processEvents()
