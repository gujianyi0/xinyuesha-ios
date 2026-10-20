"""Replay real touch gestures against the shipped LogEdit and TapHandler."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.setdefault("QT_QPA_PLATFORM","offscreen");os.environ.setdefault("QT_QUICK_BACKEND","software")
from PySide6.QtCore import QUrl,QEventLoop,QTimer,QMetaObject,Q_RETURN_ARG,QPoint
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument("--payload",type=Path,required=True);p.add_argument("--work-dir",type=Path,required=True);p.add_argument("--measure-only",action="store_true");a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
C=Path(__file__).resolve().parents[1];app=QGuiApplication([])
def pump(ms):
 loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 base=Path(temp)
 def put(name,s):
  dest=base/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(s,encoding="utf8")
 put("Fk/qmldir","module Fk\n"+"".join("singleton "+n+" 1.0 "+n+".qml\n" for n in ["Cpp","Config","Backend","Lua"]))
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
 CounterHost{id:host}
 LogEdit{id:log;x:10;y:10;width:400;height:340}
 function setup(){for(let n=0;n<60;n++)log.append({logText:"战报 "+n+" "+"很长的连续战报文字用来模拟技能日志".repeat(30)});log.currentIndex=0;log.positionViewAtBeginning();}
 function adapt(){host.refreshCompatibility(log);}
 function live(){log.currentIndex=log.count-1;log.positionViewAtEnd();stream.running=true;}
 function stopLive(){stream.running=false;}
 Timer{id:stream;interval:30;repeat:true;onTriggered:log.append({logText:"新的实时战报"+"很长的连续战报文字用来模拟技能日志".repeat(30)})}
 function beginning(){log.cancelFlick();log.currentIndex=0;log.positionViewAtBeginning();}
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
 print(json.dumps(result,indent=2));(a.work_dir/"result.json").write_text(json.dumps(result,indent=2),encoding="utf8")
