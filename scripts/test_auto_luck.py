"""Exercise the production auto-luck controls with server request/reply timing."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software');os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QPoint,Qt,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from PySide6.QtQuick import QQuickWindow
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
s=(a.payload/'card-counter/CounterHost.qml').read_text(encoding='utf8');start=s.index('  // BEGIN AUTO LUCK CARD:');end=s.index('  // END AUTO LUCK CARD',start);fragment=s[start:end]
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
font=Path("C:/Windows/Fonts/msyh.ttc")
if font.exists():
 i=QFontDatabase.addApplicationFont(str(font));app.setFont(QFont(QFontDatabase.applicationFontFamilies(i)[0]))
def pump(ms=100):
 l=QEventLoop();QTimer.singleShot(ms,l.quit);l.exec()
with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
 b=Path(tmp)
 shutil.copyfile(a.payload/'card-counter/LuckGoals.js',b/'LuckGoals.js')
 def put(n,s):
  f=b/n;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Config','Lua','Backend','Mediator']))
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool observing:false;property bool replaying:false;}')
 put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject{property var selfPlayer:({id:1});property var replies:[];signal used(string button)
 function tr(s){return ({crossbow:"诸葛连弩",spear:"丈八蛇矛",jink:"闪",slash:"杀",peach:"桃"})[s]||s;}
 function updateRequestUI(type,button){if(type!=="Button")throw Error("wrong UI command");replies=replies.concat([button]);used(button);}
}''')
 put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject{property int requestId:0;property double stamp:0;property real timeout:20
 function getRequestData(){return {id:requestId,timestamp:stamp,timeout:timeout};}}
''')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import Fk
import "LuckGoals.js" as LuckGoals
Window{id:win;width:1000;height:650;visible:true
 Item{id:host;property var currentScene:scene;property bool directionalLuckEnabled:true;property string directionalLuckGoals:"诸葛连弩/丈八蛇矛"
 function disposeRoomItem(item){if(item)item.destroy();}
 FRAGMENT
 }
 QtObject{id:room;property int dashboardId:1;property string prompt:"";property bool okEnabled:true;property bool cancelEnabled:true;property var dashboard:({handcards:[]})}
 Item{id:scene;width:1000;height:650;property var dataModel:room}
 Connections{target:Lua;function onUsed(button){Qt.callLater(function(){room.prompt="";room.okEnabled=false;room.cancelEnabled=false;Mediator.commandGot(null,"ReplyToServer",button==="OK"?"1":"__cancel");});}}
 function hand(names){room.dashboard={handcards:names.map((n,i)=>({cardId:i+1,name:n,trueName:n.split("__").pop(),known:true}))};}
 function request(left){Backend.requestId++;Backend.stamp=Date.now();nativeRequest(left);}
 function nativeRequest(left){Mediator.commandGot(null,"CancelRequest",null);room.prompt="";room.okEnabled=false;room.cancelEnabled=false;room.prompt="#AskForLuckCard:::"+left;room.okEnabled=true;room.cancelEnabled=true;Mediator.commandGot(null,"AskForSkillInvoke",["AskForLuckCard",room.prompt]);}
 function cancelOnly(){room.prompt="";room.okEnabled=false;room.cancelEnabled=false;Mediator.commandGot(null,"CancelRequest",null);}
 function queuedNativeRequest(left){room.prompt="";room.okEnabled=false;room.cancelEnabled=false;Mediator.commandGot(null,"CancelRequest",null);deferredRequest.left=left;deferredRequest.restart();}
 Timer{id:deferredRequest;property int left:0;interval:30;onTriggered:win.nativeRequest(left)}
 function duplicate(){room.prompt=host.luckPanel.expectedPrompt;room.okEnabled=true;room.cancelEnabled=true;Mediator.commandGot(null,"AskForSkillInvoke",["AskForLuckCard",room.prompt]);}
 function otherSkill(){Mediator.commandGot(null,"AskForSkillInvoke",["skill","#AskForSkillInvoke:::skill"]);}
 function phase(){Mediator.commandGot(null,"PlayCard",[]);}
 function reset(){if(host.luckPanel){host.luckPanel.destroy();host.luckPanel=null;}Lua.replies=[];Config.observing=false;Config.replaying=false;Backend.timeout=20;room.dashboardId=1;scene.visible=true;host.currentScene=scene;}
 function find(name){const pending=[host.luckPanel];while(pending.length){const n=pending.pop();if(n.objectName===name)return n;pending.push(...Array.from(n.children||[]));}return null;}
 function goal(text){find("autoLuckGoals").text=text;}
 function state(){const p=host.luckPanel;return JSON.stringify({exists:!!p,visible:p&&p.visible,running:p&&p.running,waiting:p&&p.waiting,used:p&&p.used,status:p&&p.statusText,replies:Lua.replies});}
 function point(name){const n=find(name),p=n.mapToItem(win.contentItem,n.width/2,n.height/2);return JSON.stringify({x:p.x,y:p.y});}
 function expire(){Backend.stamp=Date.now()-60000;}
 function stale(){room.prompt="#AskForSkillInvoke:::different";}
 function manual(){Mediator.commandGot(null,"ReplyToServer","1");}
 function observer(){Config.observing=true;}
 function replay(){Config.replaying=true;}
 function unknown(){room.dashboard.handcards[0].known=false;}
 function leave(){host.currentScene=null;}
 function playerTwo(){room.dashboardId=2;}
 function parse(text){return JSON.stringify(host.luckPanel.parseGoals(text));}
}'''.replace('FRAGMENT',fragment))
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0];win.requestActivate();pump()
 def call(n,*args):return QMetaObject.invokeMethod(win,n,Q_RETURN_ARG('QVariant'),*[Q_ARG('QVariant',x) for x in args])
 def state():return json.loads(call('state'))
 def click(n):
  pt=json.loads(call('point',n));QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(pt['x']),round(pt['y'])));pump(40)
 def setup(names,left=10,goal='AK/丈八'):
  call('reset');pump();call('hand',names);call('request',left);pump(40);call('goal',goal)
 checks=[]
 call('otherSkill');assert not state()['exists'];checks.append('unrelated skills ignored')
 setup(['jink','peach']);pump(400);assert state()['replies']==[],state();checks.append('requires an explicit start click')
 click('autoLuckStart');pump(350);assert state()['replies']==['OK'] and state()['waiting'] and state()['running'],state()
 call('duplicate');pump(400);assert state()['replies']==['OK'],state();checks.append('one normal OK per server request, duplicates ignored')
 call('hand',['crossbow','slash']);call('request',9);pump(400);assert state()['replies']==['OK','Cancel'] and not state()['running'],state();checks.append('matching weapon keeps hand using normal Cancel')
 setup(['jink']);click('autoLuckStart');pump(350)
 for left in [9,8]:
  call('queuedNativeRequest',left);pump(400)
  assert state()['running'] and state()['waiting'],state()
 call('hand',['spear']);call('queuedNativeRequest',7);pump(400)
 assert state()['replies']==['OK','OK','OK','Cancel'],state();checks.append('native CancelRequest preludes, queued own replies and shared request metadata continue across three rerolls')
 setup(['jink']);click('autoLuckClose');call('request',9);pump(400)
 assert not state()['visible'] and not state()['running'] and not state()['replies'],state()
 call('nativeRequest',8);pump(400)
 assert not state()['visible'] and not state()['replies'],state();checks.append('manual close stays dismissed across later native rerolls')
 call('phase');call('request',10);pump(80)
 assert state()['visible'] and not state()['running'],state();checks.append('new luck phase can show controls again without auto starting')
 setup(['jink']);click('autoLuckStart');call('cancelOnly');pump(400)
 assert not state()['visible'] and not state()['replies'],state();checks.append('terminal native cancel stops the pending action')
 setup(['crossbow','slash','jink'],goal='连弩，杀:2');click('autoLuckStart');pump(350);assert state()['replies']==['OK'],state()
 call('hand',['crossbow','fire_slash','thunder_slash']);call('request',9);pump(400);assert state()['replies']==['OK','Cancel'],state();checks.append('AND combination with minimum count and elemental slash')
 setup(['spear','jink']);click('autoLuckStart');pump(350);assert state()['replies']==['Cancel'],state();checks.append('OR alternative matches spear')
 setup(['jink']);click('autoLuckStart');click('autoLuckStop');pump(400);assert state()['replies']==[],state();checks.append('stop cancels queued action')
 for scenario in ['stale','expire','observer','replay','unknown','playerTwo']:
  setup(['jink']);click('autoLuckStart');call(scenario);pump(400);assert state()['replies']==[],(scenario,state());checks.append(scenario+' blocks auto reply')
 setup(['jink']);click('autoLuckStart');call('manual');pump(400);assert state()['replies']==[] and not state()['running'],state();checks.append('manual takeover stops auto')
 setup(['jink'],left=0);click('autoLuckStart');pump(350);assert state()['replies']==[] and not state()['running'],state();checks.append('zero server allowance does not send')
 setup(['jink']);click('autoLuckStart');call('phase');pump(400);assert state()['replies']==[] and not state()['visible'],state();checks.append('next game phase closes control')
 setup(['jink']);click('autoLuckStart');call('leave');pump(400);assert not state()['exists'],state();checks.append('room exit destroys request controller')
 setup(['jink'],goal='杀:0');click('autoLuckStart');pump(350);assert state()['replies']==[] and not state()['running'],state()
 for text in ['', '杀:0','杀:100','杀/','桃,,杀']:
  assert json.loads(call('parse',text)) is None,text
 assert json.loads(call('parse',' AK / 丈八 :1， 杀:2 '))==[{'names':['crossbow','spear'],'count':1},{'names':['slash'],'count':2}]
 checks.append('custom goal validation and localized/internal aliases')
 setup(['jink']);click('autoLuckStart');win.hide();pump(350);assert state()['replies']==[],state();win.show();win.requestActivate();pump();assert not state()['running'],state();checks.append('background pauses without auto resume')
 setup(['jink']);pump(100);win.grabWindow().save(str(a.work_dir/'panel.png'))
 errors=[s for s in logs if any(x in s for x in ['TypeError','ReferenceError','Binding loop','Cannot assign','Unable to assign','is not a type'])];assert not errors,errors
 result={'checks':checks,'errors':errors,'qt':__import__('PySide6').__version__,'realDevice':False};(a.work_dir/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False));win.close();engine.deleteLater();app.processEvents()
