# SPDX-License-Identifier: GPL-3.0-or-later
"""Follow compatibility with missing metadata and stale presence, no network."""
import argparse,json,os,shutil,tempfile,ctypes,ctypes.util,re
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);p.add_argument('--lua-library');a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
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
 source=(base/'card-counter/SocialHost.qml').read_text(encoding='utf8').replace('  id: host','  id: host\n  property alias testJoin:joinDialog',1)
 (base/'card-counter/SocialHost.qml').write_text(source,encoding='utf8')
 put('Main.qml','''import QtQuick
import Fk
import "card-counter" as Counter
Window {
 id:win;width:1200;height:700;visible:true
 Counter.SocialHost {id:host}
 function setup(){host.profiles={"test:9527/1":{enabled:false}};host.profilesLoaded=true;Mediator.commandGot(null,"EnterLobby",[]);host.socialClient.busy=true;host.socialClient.enabled=true;host.socialClient.token="local-fixture";}
 function friend(p){host.socialClient.friends=[{id:"friend",name:"friend",code:"123456789012",presence:p}];}
 function missing(){friend({state:"playing",server:"test:9527",roomId:0,roomName:"已同步的名称"});}
 function legacy(){friend({state:"playing",server:" TEST:9527 ",roomId:0,room_id:"74",room_name:"旧版房间"});}
 function nested(){friend({state:"spectating",server:"test:9527",room:{id:76,name:"嵌套房间"}});}
 function moved(){friend({state:"playing",server:"test:9527",roomId:75});}
 function offline(){friend({state:"offline",server:"test:9527",roomId:74});}
 function follow(){host.followObserve(host.socialClient.friends[0]);}
 function confirm(){host.joinTarget(host.testJoin.targetRoom,true);}
 function close(){host.testJoin.close();Cpp.packets=[];host.socialClient.error="";}
 function oldChangeRoom(){Mediator.commandGot(null,"ChangeRoom",["room",4,15,{room_id:42,room_name:"改名房间"}]);}
 function mixedChangeRoom(){Mediator.commandGot(null,"ChangeRoom",{settings:{gameMode:"fixture",roomId:0},room_id:43,room_name:"顶层旧字段"});}
 function intent(){host.gameState="lobby";host.rememberRoomIntent(87,"旧核心无房号");Mediator.commandGot(null,"EnterRoom",[4,15,{gameMode:"fixture"}]);}
 function rooms(){Mediator.commandGot(null,"UpdateRoomList",[[81,"已同步的名称","fixture",4,4,false,false]]);}
 function ambiguousRooms(){Mediator.commandGot(null,"UpdateRoomList",[[81,"已同步的名称"],[82,"已同步的名称"]]);}
 function expireRooms(){host.publicRoomsDeadline=0;}
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
 call('setup');call('missing');assert state()['can'] and '待同步' in state()['status'] and '已同步的名称' in state()['status'],state()
 call('follow');assert state()['dialog'] and state()['target']['needsRoomId'] and state()['packets']==[{'command':'RefreshRoomList','data':''}],state()
 call('confirm');assert state()['packets']==[{'command':'RefreshRoomList','data':''}] and '自动同步' in state()['error'],state()
 assert win.findChild(QObject,'manualFollowRoom') is None,'following must not request a manual room number'
 call('ambiguousRooms');assert state()['target']['needsRoomId'],'duplicate names must not select an arbitrary room'
 call('rooms');assert state()['target']['roomId']==81 and not state()['target']['needsRoomId'],state()
 call('confirm');assert state()['packets'][-1]=={'command':'ObserveRoom','data':[81,'']},state()
 call('close');call('expireRooms')
 call('close');call('missing');call('follow');call('legacy')
 assert not state()['target']['needsRoomId'] and state()['target']['roomId']==74,'fresh presence fills the open follow dialog'
 call('confirm');assert state()['packets']==[{'command':'RefreshRoomList','data':''},{'command':'ObserveRoom','data':[74,'']}],state()
 call('close');call('legacy');assert '旧版房间' in state()['status'] and state()['can'],state()
 call('follow');call('confirm');assert state()['packets']==[{'command':'ObserveRoom','data':[74,'']}],state()
 call('close');call('nested');call('follow');call('confirm');assert state()['packets']==[{'command':'ObserveRoom','data':[76,'']}],state()
 call('close');call('legacy')
 call('close');call('follow');call('moved');call('confirm');assert state()['packets']==[] and '状态已改变' in state()['error'],state()
 call('close');call('offline');assert not state()['can'];call('follow');assert state()['packets']==[] and not state()['dialog'],state()
 call('oldChangeRoom');assert state()['roomId']==42 and state()['roomName']=='改名房间',state()
 call('mixedChangeRoom');assert state()['roomId']==43 and state()['roomName']=='顶层旧字段',state()
 call('recover');assert state()['roomId']==99 and state()['roomName']=='恢复的房间',state()
 assert invoke('warmRecover')==0,'complete room metadata must not issue repeated Lua queries'
 assert invoke('rename') is True,'a room-name-only update must schedule presence sync'
 call('close');call('intent');assert state()['roomId']==87 and state()['roomName']=='旧核心无房号',(state(),logs)
 assert state()['packets']==[],'metadata capture must never send a duplicate room request'
 errors=[s for s in logs if any(x in s for x in ['TypeError','ReferenceError','SyntaxError','Cannot assign','Unable to assign','Binding loop'])]
 assert not errors,errors
 result={'missing_room_auto_sync_no_manual_entry':True,'fresh_public_room_lookup':True,'duplicate_room_names_rejected':True,'legacy_room_fields':True,'zero_does_not_mask_legacy_id':True,'nested_room_fields':True,'selected_room_intent':True,'room_name_visible':True,'stale_and_offline_rejected':True,'room_recovery':True,'rename_sync':True,'real_network_used':False,'qml_errors':errors}
 library=a.lua_library or ctypes.util.find_library('lua5.4')
 if library:
  directory=os.add_dll_directory(str(Path(library).resolve().parent)) if os.name=='nt' else None
  lib=ctypes.CDLL(library);lib.luaL_newstate.restype=ctypes.c_void_p
  lib.luaL_openlibs.argtypes=[ctypes.c_void_p];lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
  lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
  lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
  lib.lua_close.argtypes=[ctypes.c_void_p]
  expression=re.search(r"const value=Lua.ev\('(.*?)'\);",source).group(1)
  code='''local cases={
   {settings={room_id="71",room_name="old"}},
   {settings={roomId=0,room_id="72",roomName="zero"}},
   {settings={room={id=73,name="nested"}}},
   {settings={roomId="bad",room_id=-1},room_id=74,roomName="client"}}
   for i,r in ipairs(cases) do ClientInstance=r;local v='''+expression+''';assert(v.roomId==70+i,"room recovery case "..i) end
   return "four real Lua recovery cases passed"'''
  vm=lib.luaL_newstate()
  try:
   lib.luaL_openlibs(vm)
   assert lib.luaL_loadstring(vm,code.encode())==0,lib.lua_tolstring(vm,-1,None)
   assert lib.lua_pcallk(vm,0,1,0,0,None)==0,lib.lua_tolstring(vm,-1,None)
   result['real_lua_recovery']=lib.lua_tolstring(vm,-1,None).decode()
  finally:
   lib.lua_close(vm)
   if directory:directory.close()
 print(json.dumps(result));(a.work_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8')
 win.close();engine.deleteLater();app.processEvents()
