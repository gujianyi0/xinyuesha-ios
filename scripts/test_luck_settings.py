"""Actual settings page/button + production persistence and shared goal parser."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QUrl,QTimer,QEventLoop,QMetaObject,Q_RETURN_ARG,Q_ARG,QPointF,Qt,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQuick import QQuickItem
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
s=(a.payload/'card-counter/CounterHost.qml').read_text('utf8');fragment=s[s.index('  property bool directionalLuckEnabled:'):s.index('  function adaptFunctionSettings')]
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
if Path('C:/Windows/Fonts/msyh.ttc').exists():
 font=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont(QFontDatabase.applicationFontFamilies(font)[0]))
with tempfile.TemporaryDirectory(dir=a.output) as temp:
 b=Path(temp)
 def put(name,value):
  path=b/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value,'utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Backend','Mediator']))
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"Windows";}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool observing:false;property bool replaying:false;}')
 put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
 put('Fk/Backend.qml',r'''pragma Singleton
import QtQuick
QtObject{property string stored:'{"directionalLuck":true,"future":7}';property bool fail:false;
 function readFileFromAssets(path){return stored;}function writeFileToAssets(path,value){if(fail)return false;stored=value;return true;}}
''')
 for name in ['FeedbackFeatures.qml','LuckGoals.js']:shutil.copyfile(a.payload/'card-counter'/name,b/name)
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import "LuckGoals.js" as LuckGoals
Window{id:win;width:800;height:720;visible:true
 FeedbackFeatures{id:features;owner:host}
 Item{id:host;property var currentScene:null;property bool settingsReady:false;property var clientContext:null;property var luckPanel:panel
 function disposeRoomItem(item){}
 FRAGMENT
 }
 QtObject{id:panel;property string value:"";property int stopped:0;function useSavedGoals(v){value=v;stopped++;}}
 Item{id:profile;anchors.fill:parent
 Item{property var model:ListModel{ListElement{name:"Userinfo Settings"}ListElement{name:"BG Settings"}ListElement{name:"Audio Settings"}ListElement{name:"Control Settings"}ListElement{name:"UI settings"}}}
 SwipeView{id:pages;anchors.fill:parent;Item{}Item{}Item{}Item{}Item{}}
 }
 Component.onCompleted:{features.adaptProfile(profile);pages.currentIndex=5;}
 function save(v){return host.setDirectionalLuckGoals(v);}
 function bad(){Backend.stored="invalid";}
 function fail(v){Backend.fail=v;}
 function state(){return JSON.stringify({stored:Backend.stored,goal:host.directionalLuckGoals,error:host.functionSettingsError,panel:panel.value,stopped:panel.stopped});}
}'''.replace('FRAGMENT',fragment))
 engine=QQmlApplicationEngine();engine.addImportPath(str(b.resolve()));engine.load(QUrl.fromLocalFile(str((b/'Main.qml').resolve())));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump(ms=80):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def call(name,*args):return QMetaObject.invokeMethod(win,name,Q_RETURN_ARG('QVariant'),*[Q_ARG('QVariant',v) for v in args])
 def action(name,*args):QMetaObject.invokeMethod(win,name,*[Q_ARG('QVariant',v) for v in args]);pump()
 def state():return json.loads(call('state'))
 pump(650);field=win.findChild(QQuickItem,'directionalLuckGoalInput');button=win.findChild(QQuickItem,'directionalLuckSaveGoals');assert field and button and button.isVisible(),logs
 win.grabWindow().save(str(a.output/'before.png'))
 field.setProperty('text','连弩，杀:2');pos=button.mapToScene(QPointF(button.width()/2,button.height()/2));assert 0<pos.x()<win.width() and 0<pos.y()<win.height(),(pos,button.width(),button.height());QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,pos.toPoint());pump()
 value=state();stored=json.loads(value['stored']);assert stored['directionalLuckGoals']=='连弩，杀:2' and stored['future']==7 and stored['directionalLuck'] is True,value
 assert value['panel']=='连弩，杀:2' and value['stopped']==1,value
 before=value['stored'];assert not call('save','杀:0') and state()['stored']==before
 action('fail',True);assert not call('save','桃:2') and state()['stored']==before
 action('fail',False);action('bad');assert not call('save','桃:2') and state()['stored']=='invalid'
 win.grabWindow().save(str(a.output/'settings.png'))
 bad=[x for x in logs if any(t in x for t in ['TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop'])];assert not bad,bad
 result=dict(passed=True,qt=__import__('PySide6').__version__,actualSaveButton=True,preserveOtherSettings=True,invalidAndFailedSavePreserved=True,activeControllerStopsBeforeTargetUpdate=True,physicalDevice=False)
 (a.output/'result.json').write_text(json.dumps(result,indent=2),'utf8');print(json.dumps(result));win.close()
