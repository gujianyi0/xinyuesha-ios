# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the shipped activation handler without a physical UIKit device."""
import os,re,tempfile,json,time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtCore import QUrl,QMetaObject,Qt,Q_RETURN_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
C=Path(__file__).resolve().parents[1]
s=(C/'runtime/card-counter/client-shell/main.qml').read_text(encoding='utf8')
handler=re.search(r'^  onActiveChanged: (.+)$',s,re.M).group(1)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as t:
 b=Path(t);(b/'Fk').mkdir();(b/'Fk/qmldir').write_text('module Fk\nsingleton Cpp 1.0 Cpp.qml\n');(b/'Fk/Cpp.qml').write_text("pragma Singleton\nimport QtQuick\nQtObject {property string os:'iOS'}")
 p=Path(t)/'Main.qml';p.write_text("""import QtQuick
import Fk
QtObject {id:root;property bool active:false;property bool skinDebuggerMode:false;property bool androidMode:true
 property int calls:0
 function showFullScreen(){calls++;}
 HANDLER
 function focus(){active=false;active=true;}
 function android(){Cpp.os='Android';}
 function enableDebugger(){skinDebuggerMode=true;}
 function result(){return calls;}
}""".replace('HANDLER','onActiveChanged: '+handler),encoding='utf8')
 engine=QQmlApplicationEngine();engine.addImportPath(t);engine.load(QUrl.fromLocalFile(str(p)));assert engine.rootObjects();obj=engine.rootObjects()[0]
 def call(n):QMetaObject.invokeMethod(obj,n,Qt.DirectConnection)
 def pump():
  end=time.monotonic()+.08
  while time.monotonic()<end:app.processEvents();time.sleep(.001)
 def count():return QMetaObject.invokeMethod(obj,'result',Qt.DirectConnection,Q_RETURN_ARG('QVariant'))
 for _ in range(30):call('focus');pump()
 assert count()==0,'iOS must not re-show the Qt window while UIKit changes focus'
 call('android');call('focus');pump();assert count()==1,'Android keeps its existing focus recovery'
 call('enableDebugger');call('focus');pump();assert count()==1
 print(json.dumps({'ios_activation_cycles':30,'ios_fullscreen_resets':0,'android_recovery':True,'debugger_guard':True}))
