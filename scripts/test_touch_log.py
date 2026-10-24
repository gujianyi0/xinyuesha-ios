"""Replay real touch gestures against the shipped LogEdit and TapHandler."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.setdefault("QT_QPA_PLATFORM","offscreen");os.environ.setdefault("QT_QUICK_BACKEND","software")
from PySide6.QtCore import QObject,QUrl,QEventLoop,QTimer,QMetaObject,Q_RETURN_ARG,QPoint,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest,QSignalSpy
p=argparse.ArgumentParser();p.add_argument("--payload",type=Path,required=True);p.add_argument("--work-dir",type=Path,required=True);p.add_argument("--measure-only",action="store_true");a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
C=Path(__file__).resolve().parents[1];messages=[];qInstallMessageHandler(lambda kind,context,message:messages.append(message));app=QGuiApplication([])
def pump(ms):
 loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 base=Path(temp)
 def put(name,s):
  dest=base/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(s,encoding="utf8")
 put("Fk/qmldir","module Fk\n"+"".join("singleton "+n+" 1.0 "+n+".qml\n" for n in ["Cpp","Config","Backend","Lua","Mediator"]))
 put("Fk/Mediator.qml",'pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
 put("Fk/Cpp.qml",'pragma Singleton\nimport QtQuick\nQtObject{property string os:"Android"}')
 put("Fk/Config.qml",'pragma Singleton\nimport QtQuick\nQtObject{property string roomBg:"";property string lobbyBg:"";function saveConf(){}}')
 put("Fk/Backend.qml",'pragma Singleton\nimport QtQuick\nQtObject{function readFileFromAssets(p){return "{}";}function writeFileToAssets(p,v){return true;}}')
 put("Fk/Lua.qml",'pragma Singleton\nimport QtQuick\nQtObject{function tr(s){return s;}function ev(s){return true;}}')
 put("LunarLtk/qmldir","module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n")
 put("LunarLtk/Ltk.qml",'pragma Singleton\nimport QtQuick\nQtObject{property var roomScene:null}')
 put("Fk/Widgets/qmldir","module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n")
 for source,dest in [(C/"runtime/Fk/Widgets/TapHandler.qml",base/"Fk/Widgets/TapHandler.qml"),(C/"runtime/Fk/Components/Common/LogEdit.qml",base/"LogEdit.qml"),(a.payload/"card-counter/CounterHost.qml",base/"CounterHost.qml")]:shutil.copyfile(source,dest)
 put("Main.qml",'''import QtQuick
Window {
 id:win;width:420;height:360;visible:true
 property real zoom:1
 property int repetitions:30
 CounterHost{id:host}
 LogEdit{id:log;x:10;y:10;width:400/win.zoom;height:340/win.zoom;scale:win.zoom;transformOrigin:Item.TopLeft}
 function setup(){for(let n=0;n<60;n++)log.append({logText:"战报 "+n+" "+"很长的连续战报文字用来模拟技能日志".repeat(30)});log.currentIndex=0;log.positionViewAtBeginning();}
 function adapt(){host.refreshCompatibility(log);}
 function live(){log.currentIndex=log.count-1;log.positionViewAtEnd();stream.running=true;}
 function stopLive(){stream.running=false;}
 Timer{id:stream;interval:30;repeat:true;onTriggered:log.append({logText:"新的实时战报"+"很长的连续战报文字用来模拟技能日志".repeat(30)})}
 function beginning(){log.cancelFlick();log.currentIndex=0;log.positionViewAtBeginning();}
 function middle(){log.cancelFlick();log.currentIndex=-1;log.positionViewAtIndex(Math.floor(log.count/2),ListView.Beginning);}
 function settle(){log.cancelFlick();}
 function compact(){win.zoom=.65;}
 function shortRows(){stream.running=false;repetitions=1;log.clear();for(let n=0;n<180;n++)log.append({logText:"<b>战报 "+n+"</b> <font color='green'>伤害与摸牌</font>"});log.currentIndex=-1;}
 function rowPolicy(){const pending=Array.from(log.contentItem.children),seen=new Set(),bad=[];let handlers=0;
  while(pending.length){const n=pending.pop();if(!n || seen.has(n))continue;seen.add(n);
   if("gesturePolicy" in n && "tapped" in n){handlers++;if(n.gesturePolicy!==TapHandler.DragThreshold)bad.push(String(n));}
   if(n.children)pending.push(...Array.from(n.children));if(n.data)pending.push(...Array.from(n.data));}
  return JSON.stringify({handlers:handlers,bad:bad});}
 function state(){return JSON.stringify({y:log.contentY,index:log.currentIndex,count:log.count,endGap:log.contentHeight-log.height-log.contentY});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.load(QUrl.fromLocalFile(str(base/"Main.qml")));assert engine.rootObjects();win=engine.rootObjects()[0]
 def invoke(name):return QMetaObject.invokeMethod(win,name,Q_RETURN_ARG("QVariant"))
 def state():return json.loads(invoke("state"))
 invoke("setup");pump(120);invoke("adapt");pump(80);invoke('live');pump(80);start=state();device=QTest.createTouchDevice()
 def swipe():
  QTest.touchEvent(win,device).press(0,QPoint(210,80),win).commit();pump(20)
  for y in [100,130,160,190,220,250,280]:QTest.touchEvent(win,device).move(0,QPoint(210,y),win).commit();pump(30)
  QTest.touchEvent(win,device).release(0,QPoint(210,280),win).commit();pump(180)
 swipe();after=state();invoke("stopLive");invoke("beginning");pump(50)
 # Tap still selects a log row after the drag policy adjustment.
 QTest.touchEvent(win,device).press(0,QPoint(210,120),win).commit();pump(20);QTest.touchEvent(win,device).release(0,QPoint(210,120),win).commit();pump(40);tap=state()
 result={"before":start,"after_touch_drag":after,"after_tap":tap,"scroll_distance":start["y"]-after["y"]}
 if not a.measure_only:assert result["scroll_distance"]>100,result
 # Subsequent delegates, short rich-text rows, slow presses and scaled game
 # drawers must all yield to vertical drags rather than select a row on release.
 gestures=[]
 for mode in ['long','short','scaled']:
  if mode=='short':invoke('shortRows')
  if mode=='scaled':invoke('compact')
  for hold in [20,850]:
   invoke('middle');pump(100);before=state()
   QTest.touchEvent(win,device).press(0,QPoint(210,110),win).commit();pump(hold)
   for x,y in [(212,125),(214,145),(216,170),(218,200),(220,230)]:
    QTest.touchEvent(win,device).move(0,QPoint(x,y),win).commit();pump(25)
   QTest.touchEvent(win,device).release(0,QPoint(220,230),win).commit();pump(120)
   moved=before['y']-state()['y'];invoke('settle');pump(50);policy=json.loads(invoke('rowPolicy'))
   item={'mode':mode,'press_ms':hold,'distance':moved,'index':state()['index'],'policy':policy};gestures.append(item)
   if not a.measure_only:
    assert moved>40 and state()['index']==-1,item
    assert policy['handlers']>0 and not policy['bad'],item
 errors=[m for m in messages if any(s in m for s in ['TypeError','ReferenceError','Unable to assign','Cannot assign','Binding loop'])]
 assert not errors,errors
 guard=win.findChild(QObject,'touchLogGuard')
 if not a.measure_only:
  assert guard and len(win.findChildren(QObject,'touchLogGuard'))==1,'install one guard per log view'
  pump(100);idle=QSignalSpy(guard.adaptedRowsChanged);pump(250)
  assert idle.count()==0,'an idle log must not poll its delegates'
 result.update(repeated_gestures=gestures,idle_delegate_scans=0 if not a.measure_only else None,errors=errors)
 print(json.dumps(result,indent=2));(a.work_dir/"result.json").write_text(json.dumps(result,indent=2),encoding="utf8")
