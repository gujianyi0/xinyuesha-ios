# Validate all image buttons and native completion through the generated QML.
import os,tempfile,json,shutil
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,QObject,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
ui=Path(os.environ['FK_TEST_UI'])
with tempfile.TemporaryDirectory() as t:
 b=Path(t)
 def put(n,s):
  p=b/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Lua','Config','Backend']))
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject {function tr(s){return s;}}')
 put('Fk/Config.qml','''pragma Singleton
import QtQuick
QtObject {property string lobbyBg:"old-lobby";property string roomBg:"old-room";property string ladyImg:"old-lady";property string bgmFile:"old-music";property string language:"zh_CN";property int saves:0;function saveConf(){saves++;}}''')
 put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject {property var requests:[];property var errors:[];signal backgroundPicked(string key,string file,string error);
 function pickBackground(key){requests=requests.concat([key]);}
 function showDialog(title,error){errors=errors.concat([error]);}}
''')
 shutil.copy2(ui/'Fk/Pages/Lobby/BGSetting.qml',b/'BGSetting.qml')
 put('Main.qml','''import QtQuick
import Fk
Window {width:900;height:500;visible:true
 BGSetting {anchors.fill:parent}
 function deliver(){const k=Backend.requests[Backend.requests.length-1];Backend.backgroundPicked(k,"file:///new-"+k,"");}
 function cancel(){const k=Backend.requests[Backend.requests.length-1];Backend.backgroundPicked(k,"","");}
 function state(){return JSON.stringify({requests:Backend.requests,saves:Config.saves,lobby:Config.lobbyBg,room:Config.roomBg,lady:Config.ladyImg,music:Config.bgmFile});}}
''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump():
  loop=QEventLoop();QTimer.singleShot(30,loop.quit);loop.exec()
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 pump();buttons=[o for o in win.findChildren(QObject) if o.property('text')=='...'];assert len(buttons)==4,(len(buttons),logs)
 for index in [0,1,3]:
  QMetaObject.invokeMethod(buttons[index],'clicked');pump();QMetaObject.invokeMethod(win,'deliver');pump()
 result=state();assert result=={'requests':['lobbyBg','roomBg','ladyImg'],'saves':3,'lobby':'file:///new-lobbyBg','room':'file:///new-roomBg','lady':'file:///new-ladyImg','music':'old-music'},result
 QMetaObject.invokeMethod(buttons[0],'clicked');pump();QMetaObject.invokeMethod(win,'cancel');pump();assert state()['saves']==3 and state()['lobby']==result['lobby']
 errors=[m for m in logs if any(s in m for s in ['TypeError','ReferenceError','Cannot assign','is not a type'])];assert not errors,errors
 print(json.dumps({'image_buttons':3,'native_results_saved':3,'cancel_preserves_config':True,'music_unchanged':True,'errors':errors}))
 win.close();engine.deleteLater();app.processEvents()
