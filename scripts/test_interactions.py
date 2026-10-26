"""Stock profile action row, pointer/touch gifts and cooldown; Chat captured locally."""
import argparse,json,os,shutil,tempfile,time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,QPoint,QPointF,Qt,QEventLoop,QTimer,QEvent,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
C=Path(__file__).resolve().parents[1];messages=[]
qInstallMessageHandler(lambda kind,context,message:messages.append(message));app=QGuiApplication([])
font=Path('C:/Windows/Fonts/msyh.ttc')
if font.exists():
 index=QFontDatabase.addApplicationFont(str(font));app.setFont(QFont(QFontDatabase.applicationFontFamilies(index)[0]))
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 B=Path(temp)
 def put(name,text):
  f=B/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend','Mediator','SkinBank']))
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property var self:({id:1});property string os:"Android";property string path:"/fixture"}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool replaying:false;property bool observing:false;property string roomBg:"";property string lobbyBg:"";property var enabledResourcePacks:[];property real winScale:1;property var blockedUsers:[];property bool banChangeSkin:false;}')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject{property var selfPlayer:({id:1,general:"self",deputyGeneral:""});function ev(s){return true;}function tr(s){return s;}}')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{function readFileFromAssets(p){return "{}";}function writeFileToAssets(p,v){return true;}}')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
 put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject{}')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
 put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject{property var roomScene:null;}')
 put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n')
 shutil.copy2(C/'runtime/Fk/Widgets/TapHandler.qml',B/'Fk/Widgets/TapHandler.qml')
 shutil.copy2(C/'runtime/Fk/Components/GameCommon/BasicItem.qml',B/'BasicItem.qml')
 shutil.copy2(C/'runtime/Fk/Widgets/PopupItem.qml',B/'PopupItem.qml')
 put('Fk/Components/Common/qmldir','module Fk.Components.Common\nMetroButton 1.0 MetroButton.qml\n')
 shutil.copy2(C/'runtime/Fk/Components/Common/MetroButton.qml',B/'Fk/Components/Common/MetroButton.qml')
 # Use the actual unmodified stock action row: original handlers must survive.
 stock=(C/'runtime/LunarLtk/Pages/InfoPopups/PlayerDetail.qml').read_text(encoding='utf8')
 row=stock[stock.index('  RowLayout {\n    MetroButton'):stock.index('  RowLayout {\n    spacing: 20')]
 put('PlayerDetail.qml','''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import Fk.Components.Common
import LunarLtk
ColumnLayout {id:root;anchors.fill:parent;anchors.margins:12;required property var dataModel;required property var endpoint;signal finish()
 Label{text:"Original player profile";color:"white"}
 STOCK_ROW
 Rectangle {Layout.fillWidth:true;Layout.fillHeight:true;color:"#25363b";Text{anchors.centerIn:parent;text:"Skills and equipment";color:"white"}}
 function givePresent(kind){endpoint.notifyServer("Chat",{type:2,msg:"$@"+kind+":"+dataModel.playerid});}
}'''.replace('STOCK_ROW',row))

 shutil.copytree(a.payload/'card-counter',B/'card-counter')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import LunarLtk
import "card-counter" as Counter
Window {
 id:win;width:800;height:500;visible:true
 property var sent:[];property int stockOpens:0;property int stockCloses:0;property int singleClicks:0
 property alias endpoint:client;property alias selfObject:selfPlayer
 QtObject{id:selfPlayer;property int id:1}
 QtObject{id:client;function notifyServer(command,data){win.sent=win.sent.concat([{command:command,data:data,time:Date.now()}]);}}
 Counter.CounterHost{id:counter}
 QtObject{id:target;property int playerid:2;property string screenName:"测试玩家";property int seatNumber:2;property var photoItem:null}
 QtObject{id:extra;property int playerid:3;property string screenName:"新增玩家";property int seatNumber:3;property var photoItem:null}
 QtObject{id:room;property int dashboardId:1;property list<QtObject> players:[];signal playerAdded(var model)}
 Item{id:scene;property var dataModel:room;property var popupItem:null;property alias infoPopup:profilePopup
  PopupItem{id:profilePopup;objectName:"stockPlayerDetailPopup";x:20;y:20;width:720;height:370;onClosed:win.stockCloses++}
 }
 Item{id:chat;x:20;y:10;width:350;height:120;property bool isLobby:false
  function loadSkills(){}
  ListView{visible:false;property int soundIdx:0;model:ListModel{}}
  RowLayout{anchors.fill:parent;TextInput{Layout.fillWidth:true;maximumLength:300}}
 }
 Component{id:photoFactory
  BasicItem{required property QtObject dataModel;property int playerid:dataModel.playerid;property string general:"fixture";x:650;y:200;width:100;height:130;selectable:true;onClicked:win.singleClicks++;onRightClicked:{win.stockOpens++;win.openProfile(dataModel);}}
 }
 function enter(){Ltk.roomScene=scene;counter.currentScene=scene;counter.attachRoleVoices(chat);counter.refreshCompatibility(scene);}
 function addPlayer(){room.players=[target];}
 function spawnPhoto(){target.photoItem=photoFactory.createObject(scene,{dataModel:target});}
 function replacePhoto(){const old=target.photoItem;target.photoItem=photoFactory.createObject(scene,{dataModel:target});if(old)old.destroy();}
 function addExtra(){room.players=[target,extra];room.playerAdded(extra);extra.photoItem=photoFactory.createObject(scene,{dataModel:extra});extra.photoItem.x=520;}
 function openProfile(player){const c=Qt.createComponent("PlayerDetail.qml");if(c.status!==Component.Ready){console.warn(c.errorString());return;}profilePopup.setSourceComponent(c,{dataModel:player,endpoint:client});profilePopup.open();}
 function menu(){openProfile(target);}
 function narrow(){profilePopup.width=340;}
 function wide(){profilePopup.width=720;}
 function singleGift(){const row=profilePopup.item.children.find(c=>c.children&&Array.from(c.children).some(b=>b.objectName==="allPresentActionBar"));const bar=row.children.find(c=>c.objectName==="allPresentActionBar");bar.children.find(b=>b.text==="Give Flower").clicked();}
 function observer(){Config.observing=true;}
 function replay(){Config.replaying=true;}
 function leave(){profilePopup.close();counter.currentScene=null;}
 function switchTargetId(){target.playerid=9;}
 function restoreTargetId(){target.playerid=2;}
 QtObject{id:own;property int playerid:1;property string screenName:"自己";property int seatNumber:1;property var photoItem:null}
 QtObject{id:duplicate;property int playerid:2;property string screenName:"重复";property int seatNumber:2;property var photoItem:null}
 QtObject{id:invalid;property int playerid:-1;property string screenName:"旁观";property int seatNumber:0;property var photoItem:null}
 function allPlayers(){room.players=[target,extra,own,duplicate,invalid];}
 function resetSent(){sent=[];}
 function forcePresent(){counter.sendPresent("Flower",true);}
 function state(){return JSON.stringify({rest:("presentRestSeconds" in counter ? counter.presentRestSeconds : 0),sent:sent,stockOpens:stockOpens,stockCloses:stockCloses,singleClicks:singleClicks,selected:target.photoItem && target.photoItem.selected,profileId:profilePopup.item ? profilePopup.item.dataModel.playerid : 0});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(B));engine.rootContext().setContextProperty('ClientInstance',None);engine.rootContext().setContextProperty('Self',None)
 engine.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert engine.rootObjects(),messages;win=engine.rootObjects()[0]
 engine.rootContext().setContextProperty('ClientInstance',win.property('endpoint'));engine.rootContext().setContextProperty('Self',win.property('selfObject'))
 def pump(ms):
  loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec();app.sendPostedEvents(None,QEvent.DeferredDelete)
 def call(name):
  if name=='closeMenu':
   QMetaObject.invokeMethod(win.findChild(QObject,'stockPlayerDetailPopup'),'close');pump(350);return
  QMetaObject.invokeMethod(win,name);pump(300 if name=='menu' else 80)
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 def wait_rest():
  while state()['rest'] > 0:pump(1020)
 def center(item):
  point=item.mapToScene(QPointF(item.width()/2,item.height()/2));return QPoint(round(point.x()),round(point.y()))
 def click(item):QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,center(item));pump(100)
 pump(120);call('enter');call('addPlayer');call('spawnPhoto')
 # Hold the real stock BasicItem. No custom signal handler may close its profile.
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(950);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(150)
 actions=win.findChild(QObject,'stockPlayerDetailPopup');assert actions and actions.property('visible'),('delayed photo did not open menu',state(),messages)
 assert not state()['sent'] and state()['stockOpens']==1 and state()['stockCloses']==0,state()
 egg=win.findChild(QObject,'presentEggButton');flower=win.findChild(QObject,'presentFlowerButton');assert egg and flower
 win.grabWindow().save(str(a.work_dir/'player-detail-actions.png'))
 # A single tap still selects its original target; a double tap opens once.
 call('closeMenu');pump(600);before=state()
 QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(120)
 assert not actions.property('visible') and state()['singleClicks']==before['singleClicks']+1
 assert state()['selected'] != before['selected'],'single-click selection must survive'
 pump(600);before=state()['stockOpens']
 QTest.mouseDClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250))
 pump(200)
 assert actions.property('visible') and state()['stockOpens']==before+1,('mouse double tap',state(),messages)
 assert state()['profileId']==2
 call('closeMenu');pump(600);call('addExtra')
 profile_touch=QTest.createTouchDevice();point=QPoint(570,250);before=state()['stockOpens']
 for _ in range(2):
  QTest.touchEvent(win,profile_touch).press(0,point,win).commit();pump(40)
  QTest.touchEvent(win,profile_touch).release(0,point,win).commit();pump(60)
 pump(200)
 assert actions.property('visible') and state()['stockOpens']==before+1 and state()['profileId']==3,('new player touch double tap',state(),messages)
 assert not state()['sent'],'opening profiles must not send gifts'
 # A physical hold must not auto-repeat or send before the release click.
 call('addExtra');call('allPlayers');call('menu');call('resetSent')
 egg=win.findChild(QObject,'presentEggButton');flower=win.findChild(QObject,'presentFlowerButton')
 assert len(win.findChildren(QObject,'allPresentActionBar'))==1
 call('narrow')
 bar=win.findChild(QObject,'allPresentActionBar')
 for item in bar.childItems():
  if item.isVisible():assert item.x()>=0 and item.x()+item.width()<=bar.width()+1,(item,bar.width())
 win.grabWindow().save(str(a.work_dir/'player-detail-narrow.png'));call('wide')
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(1900)
 assert not state()['sent'], 'Hold must not fire a burst'
 QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,center(egg));pump(100)
 assert [x['data']['msg'] for x in state()['sent']]==['$@Egg:2']
 click(flower);pump(1700)
 egg_sends=state()['sent'];assert [x['data']['msg'] for x in egg_sends]==['$@Egg:2','$@Egg:3'],egg_sends
 assert egg_sends[1]['time']-egg_sends[0]['time'] >= 1500
 assert state()['rest']>0 and not flower.property('enabled')
 call('closeMenu');call('menu');flower=win.findChild(QObject,'presentFlowerButton');call('forcePresent');assert state()['sent']==egg_sends,'reopening cannot bypass cooldown'
 wait_rest();call('resetSent')
 device=QTest.createTouchDevice();point=center(flower)
 QTest.touchEvent(win,device).press(0,point,win).commit();pump(80)
 assert not state()['sent']
 QTest.touchEvent(win,device).release(0,point,win).commit();pump(3400)
 flowers=state()['sent'];assert [x['data']['msg'] for x in flowers]==['$@Flower:2','$@Flower:3','$@Flower:1'],flowers
 assert state()['rest']>0
 wait_rest();egg=win.findChild(QObject,'presentEggButton');call('resetSent');click(egg);call('leave');left=state()['sent'];pump(1800)
 assert len(left)==1 and state()['sent']==left and not actions.property('visible'),'room leave cancels remaining recipients'
 call('enter');call('menu');flower=win.findChild(QObject,'presentFlowerButton');wait_rest();call('resetSent');click(flower);call('switchTargetId');pump(3400)
 assert all(x['data']['msg']!='$@Flower:9' for x in state()['sent']), 'queue must not retarget a changed id'
 call('restoreTargetId');call('replacePhoto');call('menu');call('closeMenu')
 QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(950);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));pump(100)
 assert actions.property('visible'),('replacement photo entry remains usable',state(),messages)
 call('closeMenu');pump(600);before=state()['stockOpens']
 QTest.mouseDClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250));QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,QPoint(700,250))
 pump(200)
 assert actions.property('visible') and state()['stockOpens']==before+1,('replacement photo double tap',state(),messages)
 assert not win.findChild(QObject,'playerPresentActions') and not win.findChild(QObject,'playerInteractionButton')
 call('singleGift');pump(350);assert state()['sent'][-1]['data']['msg']=='$@Flower:2' and not actions.property('visible')
 call('menu');call('replay');assert not win.findChild(QObject,'presentEggButton').property('enabled')
 errors=[m for m in messages if any(t in m for t in ['TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop','is not a type'])]
 assert not errors,errors
 result={'tap_all':True,'eggs_exclude_self':True,'flowers_include_self':True,'duplicate_and_observer_ids_filtered':True,'mouse_hold_does_not_repeat':True,'touch_click':True,'minimum_interval_ms':egg_sends[1]['time']-egg_sends[0]['time'],'shared_cooldown_seconds':10,'leave_cancels_queue':True,'changed_ids_not_retargeted':True,'delayed_and_replacement_photo':True,'stock_profile_preserved':True,'single_gifts_preserved':True,'wrapped_action_row':True,'extra_dialog_removed':True,'errors':errors}
 result.update(mouse_double_tap_profile=True,touch_double_tap_added_player=True,replacement_photo_double_tap=True,single_click_selection_preserved=True,opening_profile_sends_nothing=True)
 (a.work_dir/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False,indent=2))
 win.close();engine.deleteLater();pump(30)
