"""Real pointer holds and delayed player-photo discovery; Chat is captured locally."""
import argparse,json,os,shutil,tempfile,time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,QPoint,QPointF,Qt,QEventLoop,QTimer,QEvent,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
C=Path(__file__).resolve().parents[1];messages=[]
qInstallMessageHandler(lambda kind,context,message:messages.append(message));app=QGuiApplication([])
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 B=Path(temp)
 def put(name,text):
  f=B/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend','Mediator','SkinBank']))
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"Android";property string path:"/fixture"}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool replaying:false;property bool observing:false;property string roomBg:"";property string lobbyBg:"";property var enabledResourcePacks:[];}')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject{property var selfPlayer:({id:1,general:"self",deputyGeneral:""});function ev(s){return true;}function tr(s){return s;}}')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{function readFileFromAssets(p){return "{}";}function writeFileToAssets(p,v){return true;}}')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
 put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject{}')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
 put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject{property var roomScene:null;}')
 put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n')
 shutil.copy2(C/'runtime/Fk/Widgets/TapHandler.qml',B/'Fk/Widgets/TapHandler.qml')
 shutil.copy2(C/'runtime/Fk/Components/GameCommon/BasicItem.qml',B/'BasicItem.qml')
 shutil.copytree(a.payload/'card-counter',B/'card-counter')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import "card-counter" as Counter
Window {
 id:win;width:800;height:500;visible:true
 property var sent:[];property int stockOpens:0;property int stockCloses:0
 property alias endpoint:client;property alias selfObject:selfPlayer
 QtObject{id:selfPlayer;property int id:1}
 QtObject{id:client;function notifyServer(command,data){win.sent=win.sent.concat([{command:command,data:data,time:Date.now()}]);}}
 Counter.CounterHost{id:counter}
 QtObject{id:target;property int playerid:2;property string screenName:"测试玩家";property int seatNumber:2;property var photoItem:null}
 QtObject{id:extra;property int playerid:3;property string screenName:"新增玩家";property int seatNumber:3;property var photoItem:null}
 QtObject{id:room;property list<QtObject> players:[];signal playerAdded(var model)}
 Item{id:scene;property var dataModel:room;property var popupItem:null
  function closeInfoPopup(){win.stockCloses++;}
 }
 Item{id:chat;x:20;y:10;width:350;height:120;property bool isLobby:false
  function loadSkills(){}
  ListView{visible:false;property int soundIdx:0;model:ListModel{}}
  RowLayout{anchors.fill:parent;TextInput{Layout.fillWidth:true;maximumLength:300}}
 }
 Component{id:photoFactory
  BasicItem{required property QtObject dataModel;property int playerid:dataModel.playerid;property string general:"fixture";x:650;y:200;width:100;height:130;selectable:false;onRightClicked:win.stockOpens++}
 }
 function enter(){counter.currentScene=scene;counter.attachRoleVoices(chat);counter.refreshCompatibility(scene);}
 function addPlayer(){room.players=[target];}
 function spawnPhoto(){target.photoItem=photoFactory.createObject(scene,{dataModel:target});}
 function replacePhoto(){const old=target.photoItem;target.photoItem=photoFactory.createObject(scene,{dataModel:target});if(old)old.destroy();}
 function addExtra(){room.players=[target,extra];room.playerAdded(extra);extra.photoItem=photoFactory.createObject(scene,{dataModel:extra});extra.photoItem.x=520;}
 function menu(){counter.showPlayerActions(target);}
 function observer(){Config.observing=true;}
 function replay(){Config.replaying=true;}
 function leave(){counter.currentScene=null;}
 function switchTargetId(){target.playerid=9;}
 function restoreTargetId(){target.playerid=2;}
 function resetSent(){sent=[];}
 function forcePresent(){counter.sendPresent("Flower",true);}
 function state(){return JSON.stringify({rest:("presentRestSeconds" in counter ? counter.presentRestSeconds : 0),sent:sent,watchers:counter.playerActionWatchers.length,stockOpens:stockOpens,stockCloses:stockCloses});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(B));engine.rootContext().setContextProperty('ClientInstance',None);engine.rootContext().setContextProperty('Self',None)
 engine.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert engine.rootObjects(),messages;win=engine.rootObjects()[0]
 engine.rootContext().setContextProperty('ClientInstance',win.property('endpoint'));engine.rootContext().setContextProperty('Self',win.property('selfObject'))
 def pump(ms):
  loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec();app.sendPostedEvents(None,QEvent.DeferredDelete)
 def call(name):
  if name=='closeMenu':
   QMetaObject.invokeMethod(win.findChild(QObject,'playerPresentActions'),'close');pump(80);return
  QMetaObject.invokeMethod(win,name);pump(300 if name=='menu' else 80)
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 def wait_rest():
  while state()['rest'] > 0:pump(1020)
 def center(item):
  point=item.mapToScene(QPointF(item.width()/2,item.height()/2));return QPoint(round(point.x()),round(point.y()))
 def click(item):QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,center(item));pump(100)
 pump(120);call('enter');call('addPlayer');assert state()['watchers']==1,state();call('spawnPhoto')
 # No direct attachPlayerActions call: the native-like photoItem notification
 # must bind a card created after the initial compatibility pass.
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(950);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(150)
 actions=win.findChild(QObject,'playerPresentActions');assert actions and actions.property('visible'),('delayed photo did not open menu',state(),messages)
 assert not state()['sent'] and state()['stockOpens']==1 and state()['stockCloses']>=1,state()
 egg=win.findChild(QObject,'presentEggButton');flower=win.findChild(QObject,'presentFlowerButton');assert egg and flower
 win.grabWindow().save(str(a.work_dir/'interaction-menu.png'))
 click(egg);assert actions.property('visible') and len(state()['sent'])==1,state()
 assert state()['sent'][-1]['data']=={'type':2,'msg':'$@Egg:2'},state()
 pump(1600);call('resetSent')
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(flower));pump(2400);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,center(flower));pump(100)
 held=state()['sent'];assert len(held)==2 and all(x['data']['msg']=='$@Flower:2' for x in held),held
 assert held[1]['time']-held[0]['time']>=1500,held
 pump(1750);assert state()['sent']==held,'release must stop repeating'
 wait_rest()
 call('resetSent');point=center(egg)
 device=QTest.createTouchDevice();QTest.touchEvent(win,device).press(0,point,win).commit();pump(2400);QTest.touchEvent(win,device).release(0,point,win).commit();pump(100)
 touch=state()['sent'];assert len(touch)==2 and all(x['data']['msg']=='$@Egg:2' for x in touch),touch
 pump(1750);assert state()['sent']==touch,'touch release must stop repeating'
 wait_rest()
 call('resetSent');QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(flower));pump(750);QTest.mouseMove(win,QPoint(10,480));pump(1900);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(10,480));pump(80)
 moved=state()['sent'];assert len(moved)==1,'moving off the button must stop repeating'
 pump(1600);call('menu');call('resetSent')
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(750);call('closeMenu');closed=state()['sent'];pump(1900);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(100)
 assert len(closed)==1 and state()['sent']==closed,('closing the menu must cancel a hold',closed,state())
 call('replacePhoto');QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(950);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(100)
 assert actions.property('visible') and state()['stockOpens']==2,'replacement photo must remain bound once'
 call('closeMenu');entry=win.findChild(QObject,'playerInteractionButton');assert entry and entry.property('visible');click(entry)
 assert actions.property('visible'),'chat interaction entry must open the same menu'
 call('closeMenu');call('addExtra');assert state()['watchers']==2,state()
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,QPoint(570,250));pump(950);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(570,250));pump(100)
 assert actions.property('visible') and state()['stockOpens']==3,'late added player must be interactive'
 call('menu');call('observer');pump(1600);call('resetSent');click(flower)
 assert state()['sent'][-1]['data']['msg']=='$@Flower:2','observer UI must use the same target protocol'
 pump(1600);call('resetSent');QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(750);call('switchTargetId');changed=state()['sent'];pump(1900);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(80)
 assert len(changed)==1 and state()['sent']==changed,('a held action must never move to another target id',changed,state())
 call('restoreTargetId');call('menu');pump(1600);call('resetSent');QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(flower));pump(750);call('leave');left=state()['sent'];pump(1900);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,center(flower));pump(80)
 assert len(left)==1 and state()['sent']==left and not actions.property('visible') and state()['watchers']==0,'leaving must stop repeats and dispose player watchers'
 burst_result={}
 # Only the Android payload has this new policy; retain older platform behavior.
 counter=win.findChild(QObject,'fkCounterHost')
 if counter.metaObject().indexOfProperty('presentRestSeconds') >= 0:
  call('enter');call('menu');wait_rest();pump(1600);call('resetSent')
  assert actions.property('width') <= 280 and actions.property('height') <= 260, (actions.property('width'),actions.property('height'))
  QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(5350)
  burst=state()['sent'];assert len(burst)==4,burst
  assert burst[-1]['time']-burst[0]['time'] < 5000,burst
  assert 9 <= state()['rest'] <= 10 and not egg.property('enabled') and not flower.property('enabled'),state()
  win.grabWindow().save(str(a.work_dir/'interaction-cooldown.png'))
  QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(80)
  call('closeMenu');call('menu');call('switchTargetId');call('forcePresent');pump(250)
  assert state()['sent']==burst and not flower.property('enabled'), 'Reopen/target/other gift bypassed shared cooldown'
  wait_rest();assert state()['sent']==burst, 'Holding through expiry must not resume automatically'
  call('restoreTargetId');click(flower)
  assert len(state()['sent'])==len(burst)+1 and state()['sent'][-1]['data']['msg']=='$@Flower:2',state()
  burst_result={'max_burst_ms':5000,'cooldown_ms':10000,'burst_sends':len(burst),'shared_cooldown':True,'reopen_and_target_bypass_blocked':True,'resume_requires_new_press':True,'dialog_width':actions.property('width'),'dialog_height':actions.property('height')}
 call('enter');call('menu');call('replay');assert not actions.property('visible'),'replays cannot send interactions'
 errors=[m for m in messages if any(s in m for s in ['TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop','is not a type'])]
 assert not errors,errors
 result={'burst_policy':burst_result,'delayed_photo':True,'replacement_photo':True,'added_player':True,'chat_entry':True,'mouse_hold_count':len(held),'touch_hold_count':len(touch),'minimum_interval_ms':held[1]['time']-held[0]['time'],'release_cancel':True,'move_out_cancel':True,'close_cancel':True,'target_change_guard':True,'leave_cleanup':True,'replay_guard':True,'errors':errors}
 (a.work_dir/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False,indent=2))
 win.close();engine.deleteLater();pump(30)
