"""Exercise the shipped CounterHost shortcut with mouse and physical touch events."""
import argparse,json,os,re,shutil,tempfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,QPoint,QPointF,Qt,QEventLoop,QTimer,QEvent,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);p.add_argument('--baseline',action='store_true')
a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
C=Path(__file__).resolve().parents[1];messages=[]
qInstallMessageHandler(lambda k,c,m:messages.append(m));app=QGuiApplication([])
def pump(ms=80):
 loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec();app.sendPostedEvents(None,QEvent.DeferredDelete)
with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
 B=Path(tmp)
 from qml_spine_stub import install_spine_stub
 install_spine_stub(B)
 def put(name,text):
  f=B/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend','Mediator','SkinBank']))
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"Android";property string path:"/fixture";}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool replaying:false;property bool observing:false;property string roomBg:"";property string lobbyBg:"";property var enabledResourcePacks:[];property real winScale:1;property var blockedUsers:[];property bool banChangeSkin:false;}')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject{function ev(s){return true;}function tr(s){return s;}}')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{property string prefs:\'{"directionalLuck":false,"future":7}\';property bool fail:false;function readFileFromAssets(p){return p==="function-settings.json"?prefs:"{}";}function writeFileToAssets(p,v){if(fail)return false;if(p==="function-settings.json")prefs=v;return true;}}')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{property int chats:0;signal commandGot(var sender,string command,var data);function notify(sender,command,data){if(command==="IWantToChat")chats++;commandGot(sender,command,data);}}')
 put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject{}')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
 put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject{property var roomScene:null;}')
 put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n')
 shutil.copy2(C/'runtime/Fk/Widgets/TapHandler.qml',B/'Fk/Widgets/TapHandler.qml')
 shutil.copy2(C/'runtime/Fk/Components/GameCommon/BasicItem.qml',B/'BasicItem.qml')
 shutil.copytree(a.payload/'card-counter',B/'card-counter')
 stock=(C/'runtime/Fk/Pages/Common/RoomPage.qml').read_text(encoding='utf8')
 open_chat=re.search(r'  function openChat\(\) \{.*?\n  \}',stock,re.S).group()
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import "card-counter" as Counter
Window {
 id:win;width:800;height:500;visible:true
 property int cardClicks:0;property int buttonClicks:0;property int cardDoubles:0
 Counter.CounterHost{id:counter;bootstrapReady:true}
 Item{id:table;anchors.fill:parent
  Item{id:scene;objectName:"testScene";width:800;height:500
   property var dataModel:({players:[]});property alias infoPopup:info;property var popupItem:null;property var agItem:null
   Item{id:info;visible:false;property var item:null}
   Rectangle{anchors.fill:parent;color:"#24353d"}
   BasicItem{x:20;y:20;width:120;height:150;onClicked:win.cardClicks++;onDoubleClicked:win.cardDoubles++;Rectangle{anchors.fill:parent;color:"tan"}}
   Button{x:20;y:400;width:120;height:50;text:"Game action";onClicked:win.buttonClicks++}
  }
 }
 Popup{id:roomDrawer;objectName:"testChatDrawer";width:300;height:400;modal:true;closePolicy:Popup.NoAutoClose;TextField{anchors.centerIn:parent;placeholderText:"Chat"}}
 Connections{target:Mediator;function onCommandGot(sender,command,data){if(command==="IWantToChat")win.openChat();}}
 OPEN_CHAT
 function attach(){counter.currentScene=scene;}
 function release(){counter.releaseScene();}
 function repeatAttach(){counter.currentScene=scene;counter.syncScene();}
 function closeChat(){roomDrawer.close();}
 function infoOn(){scene.infoPopup.visible=true;}function infoOff(){scene.infoPopup.visible=false;}
 function skillOn(){scene.popupItem={active:true};}function skillOff(){scene.popupItem=null;}
 function agOn(){scene.agItem={active:true};}function agOff(){scene.agItem=null;}
 function hideScene(){scene.visible=false;}function showScene(){scene.visible=true;}
 function scaleScene(){scene.scale=.6;scene.transformOrigin=Item.TopLeft;}
 function resetScale(){scene.scale=1;}
 function disableShortcut(){counter.setBackgroundChatEnabled(false);}
 function enableShortcut(){counter.setBackgroundChatEnabled(true);}
 function failedShortcutSave(){Backend.fail=true;counter.setBackgroundChatEnabled(false);Backend.fail=false;}
 function reloadShortcut(){counter.backgroundChatEnabled=true;counter.preferencesLoaded=false;counter.settingsReady=false;counter.settingsReady=true;}
 function preferenceState(){return JSON.stringify({stored:JSON.parse(Backend.prefs),enabled:counter.backgroundChatEnabled,error:counter.functionSettingsError});}
 function nativeShortcut(){counter.currentScene=null;Qt.createQmlObject('import QtQuick; import Fk; MouseArea {objectName:"roomBackgroundChatShortcut";anchors.fill:parent;z:-1;onDoubleClicked: Mediator.notify(parent,"IWantToChat")}',scene,"native-existing");counter.currentScene=scene;}
 function state(){return JSON.stringify({attached:counter.currentScene===scene,shortcutObject:!!counter.backgroundChatShortcut,chats:Mediator.chats,drawer:roomDrawer.visible,cards:cardClicks,cardDoubles:cardDoubles,buttons:buttonClicks,shortcuts:scene.children.filter(c=>c.objectName==="roomBackgroundChatShortcut").length});}
}'''.replace('OPEN_CHAT',open_chat))
 engine=QQmlApplicationEngine();engine.addImportPath(str(B));engine.rootContext().setContextProperty('ClientInstance',None);engine.rootContext().setContextProperty('Self',None)
 engine.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert engine.rootObjects(),messages;win=engine.rootObjects()[0]
 def call(name):QMetaObject.invokeMethod(win,name);pump()
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 def mouse_double(pt=QPoint(400,250)):
  pump(550);QTest.mouseDClick(win,Qt.LeftButton,Qt.NoModifier,pt);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,pt);pump()
 device=QTest.createTouchDevice()
 def tap(pt):
  QTest.touchEvent(win,device).press(0,pt,win).commit();pump(35)
  QTest.touchEvent(win,device).release(0,pt,win).commit();pump(60)
 def touch_double(pt=QPoint(400,250)):
  pump(550);tap(pt);tap(pt);pump()
 pump(120);call('attach');assert state()['attached'],state();mouse_double();baseline=state()
 if a.baseline:
  assert baseline['chats']==0 and not baseline['drawer'],baseline
  touch_double();assert state()['chats']==0,state()
  result={'baselineMissingMouseAndTouchShortcut':True,'qt':__import__('PySide6').__version__,'realDevice':False}
 else:
  assert baseline['chats']==1 and baseline['drawer'] and baseline['shortcuts']==1,(baseline,messages)
  checks=['mouse double-click opens the existing room chat action exactly once']
  call('closeChat');touch_double();assert state()['chats']==2 and state()['drawer'],state()
  checks.append('two physical touch taps open the same chat drawer exactly once')
  call('closeChat');pump(550);QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(400,250));pump();assert state()['chats']==2,state()
  pump(550);tap(QPoint(400,250));pump(550);tap(QPoint(400,250));assert state()['chats']==2,state()
  checks.append('single clicks and taps outside the double-tap interval do not open chat')
  for gesture in [mouse_double,touch_double]:
   gesture(QPoint(70,70));gesture(QPoint(70,425));assert state()['chats']==2,state()
  assert state()['cards']>0 and state()['cardDoubles']>0 and state()['buttons']>0,state()
  checks.append('stock BasicItem card and button input stays exclusive to those controls')
  for on,off in [('infoOn','infoOff'),('skillOn','skillOff'),('agOn','agOff'),('hideScene','showScene')]:
   call(on);touch_double();assert state()['chats']==2,state();call(off)
  checks.append('info, skill, AG popups and hidden tables block background chat')
  pump(550);QTest.touchEvent(win,device).press(0,QPoint(400,250),win).commit();pump(30)
  QTest.touchEvent(win,device).move(0,QPoint(470,320),win).commit();pump(60)
  QTest.touchEvent(win,device).release(0,QPoint(470,320),win).commit();pump();assert state()['chats']==2,state()
  checks.append('background dragging does not open chat')
  pump(550);tap(QPoint(400,250));QTest.touchEvent(win,device).press(0,QPoint(400,250),win).commit();pump(40)
  QTest.touchEvent(win,device).move(0,QPoint(470,320),win).commit();pump(60)
  QTest.touchEvent(win,device).release(0,QPoint(470,320),win).commit();pump();assert state()['chats']==2,state()
  checks.append('dragging the second tap cancels the double-tap action')
  call('scaleScene');touch_double(QPoint(240,150));assert state()['chats']==3 and state()['drawer'],state();call('closeChat');call('resetScale')
  checks.append('scaled room coordinates retain touch double-tapping')
  call('release');assert state()['shortcuts']==0,state();touch_double();assert state()['chats']==3,state()
  call('attach');call('attach');assert state()['shortcuts']==1,state();touch_double();assert state()['chats']==4,state();call('closeChat')
  checks.append('leaving and reattaching cleans up without duplicate handlers')
  call('disableShortcut');mouse_double();touch_double();assert state()['chats']==4 and not state()['drawer'],state()
  prefs=json.loads(QMetaObject.invokeMethod(win,'preferenceState',Q_RETURN_ARG('QVariant')))
  assert prefs['stored']=={'directionalLuck':False,'future':7,'backgroundChat':False} and not prefs['enabled'],prefs
  call('reloadShortcut');touch_double();assert state()['chats']==4,state()
  call('enableShortcut');call('failedShortcutSave');touch_double();assert state()['chats']==5 and state()['drawer'],state();call('closeChat')
  checks.append('disable persists, preserves other settings and blocks mouse/touch immediately; failed writes keep the enabled value')
  call('nativeShortcut');assert state()['shortcuts']==1,state();mouse_double();assert state()['chats']==6,state();call('closeChat')
  call('disableShortcut');mouse_double();assert state()['chats']==6,state();call('enableShortcut');mouse_double();assert state()['chats']==7,state();call('closeChat')
  checks.append('an existing native iOS shortcut is reused without a second listener')
  result={'checks':checks,'state':state(),'qt':__import__('PySide6').__version__,'testedPayload':str(a.payload),'realDevice':False}
 errors=[m for m in messages if any(s in m for s in ['TypeError','ReferenceError','SyntaxError','Cannot assign','Unable to assign'])]
 assert not errors,errors
 (a.work_dir/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False))
 win.close();engine.deleteLater();app.processEvents()
