# SPDX-License-Identifier: GPL-3.0-or-later
"""Follow compatibility with missing metadata and stale presence, no network."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg));app=QGuiApplication([])
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 base=Path(temp)
 def put(name,s):
  p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Config','Cpp','Lua','Backend','SkinBank','Mediator']))
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property string serverAddr:"test";property int serverPort:9527;property bool consoleStartRequested:false;property bool replaying:false;property bool observing:false;property string screenName:"fixture";property string password:"";}')
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject {property var self:({id:1,screenName:"fixture",avatar:""});property var packets:[];function notifyServer(c,d){packets=packets.concat([{command:c,data:d}]);}}')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject {property var room:({});property int queries:0;function tr(s){return s;}function ev(s){queries++;return room;}function getPlayersAndObservers(){return [];}}')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject {function readFileFromAssets(p){return "";}function writeFileToAssets(p,v){return true;}}')
 put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject {function getGeneralExtraPic(a,b){return "";}function getGeneralPicture(a){return "";}}')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject {signal commandGot(var sender,string command,var data)}')
 shutil.copytree(a.payload/'card-counter',base/'card-counter')
 source=(base/'card-counter/SocialHost.qml').read_text(encoding='utf8').replace('  id: host','  id: host\n  property alias testJoin:joinDialog\n  property alias testRoom:manualFollowRoom',1)
 (base/'card-counter/SocialHost.qml').write_text(source,encoding='utf8')
 put('Main.qml','''import QtQuick
import Fk
import "card-counter" as Counter
Window {
 id:win;width:1200;height:700;visible:true
 Counter.SocialHost {id:host}
 function setup(){host.profiles={"test:9527/1":{enabled:false}};host.profilesLoaded=true;Mediator.commandGot(null,"EnterLobby",[]);host.socialClient.busy=true;host.socialClient.enabled=true;host.socialClient.token="local-fixture";}
 function friend(p){host.socialClient.friends=[{id:"friend",name:"friend",code:"123456789012",presence:p}];}
 function missing(){friend({state:"playing",server:"test:9527",roomId:0});}
 function legacy(){friend({state:"playing",server:" TEST:9527 ",room_id:"74",room_name:"旧版房间"});}
 function moved(){friend({state:"playing",server:"test:9527",roomId:75});}
 function offline(){friend({state:"offline",server:"test:9527",roomId:74});}
 function follow(){host.followObserve(host.socialClient.friends[0]);}
 function invalidRoom(){host.testRoom.text="abc";}
 function manualRoom(){host.testRoom.text="321";}
 function confirm(){host.joinTarget(host.testJoin.targetRoom,true);}
 function close(){host.testJoin.close();Cpp.packets=[];host.socialClient.error="";}
 function oldChangeRoom(){Mediator.commandGot(null,"ChangeRoom",["room",4,15,{room_id:42,room_name:"改名房间"}]);}
 function recover(){host.roomId=0;host.roomName="";Lua.room={roomId:99,roomName:"恢复的房间"};host.recoverRoomDetails();}
 function warmRecover(){const q=Lua.queries;for(let i=0;i<1000;i++)host.recoverRoomDetails();return Lua.queries-q;}
 function rename(){const api=host.socialClient;api.presenceDirty=false;api.bind(Object.assign({},api.context,{roomName:"仅修改名称"}));return api.presenceDirty;}
 function state(){return JSON.stringify({can:host.canFollowObserve(host.socialClient.friends[0]),status:host.friendStatus(host.socialClient.friends[0]),dialog:host.testJoin.visible,target:host.testJoin.targetRoom,packets:Cpp.packets,error:host.socialClient.error,roomId:host.roomId,roomName:host.roomName});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.rootContext().setContextProperty('ClientInstance',None);engine.load(QUrl.fromLocalFile(str(base/'Main.qml')))
 assert engine.rootObjects(),logs
 win=engine.rootObjects()[0]
 def invoke(name):return QMetaObject.invokeMethod(win,name,Q_RETURN_ARG('QVariant'))
 def call(name):
  QMetaObject.invokeMethod(win,name);loop=QEventLoop();QTimer.singleShot(60,loop.quit);loop.exec()
 def state():return json.loads(invoke('state'))
 call('setup');call('missing');assert state()['can'] and '待同步' in state()['status'],state()
 call('follow');assert state()['dialog'] and state()['target']['needsRoomId'] and state()['packets']==[],state()
 call('invalidRoom');call('confirm');assert state()['packets']==[] and '实际房间号' in state()['error'],state()
 call('manualRoom');call('confirm');assert state()['packets']==[{'command':'ObserveRoom','data':[321,'']}],state()
 call('close');call('missing');call('follow');call('legacy')
 assert not state()['target']['needsRoomId'] and state()['target']['roomId']==74,'fresh presence fills the open follow dialog'
 call('confirm');assert state()['packets']==[{'command':'ObserveRoom','data':[74,'']}],state()
 call('close');call('legacy');assert '旧版房间' in state()['status'] and state()['can'],state()
 call('follow');call('confirm');assert state()['packets']==[{'command':'ObserveRoom','data':[74,'']}],state()
 call('close');call('follow');call('moved');call('confirm');assert state()['packets']==[] and '状态已改变' in state()['error'],state()
 call('close');call('offline');assert not state()['can'];call('follow');assert state()['packets']==[] and not state()['dialog'],state()
 call('oldChangeRoom');assert state()['roomId']==42 and state()['roomName']=='改名房间',state()
 call('recover');assert state()['roomId']==99 and state()['roomName']=='恢复的房间',state()
 assert invoke('warmRecover')==0,'complete room metadata must not issue repeated Lua queries'
 assert invoke('rename') is True,'a room-name-only update must schedule presence sync'
 errors=[s for s in logs if any(x in s for x in ['TypeError','ReferenceError','SyntaxError','Cannot assign','Unable to assign','Binding loop'])]
 assert not errors,errors
 result={'missing_room_fallback':True,'legacy_room_fields':True,'room_name_visible':True,'stale_and_offline_rejected':True,'room_recovery':True,'rename_sync':True,'real_network_used':False,'qml_errors':errors}
 print(json.dumps(result));(a.work_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8')
 win.close();engine.deleteLater();app.processEvents()
