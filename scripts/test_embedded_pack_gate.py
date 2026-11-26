"""Exercise the actual startup gate with controlled local status data; no device."""
import os,json,tempfile,shutil
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QUrl,QMetaObject,QEventLoop,QTimer,QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'work/embedded-v1-20261121';OUT.mkdir(exist_ok=True)
app=QGuiApplication([])
def pump():
    loop=QEventLoop();QTimer.singleShot(80,loop.quit);loop.exec()
with tempfile.TemporaryDirectory(dir=OUT) as tmp:
    base=Path(tmp);(base/'Fk').mkdir()
    (base/'Fk/qmldir').write_text('module Fk\nsingleton Backend 1.0 Backend.qml\n')
    (base/'Fk/Backend.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property string status: ""; property string written: "";
 function existsInAssets(p) { return status.length > 0; }
 function readFileFromAssets(p) { return status; }
 function writeFileToAssets(p,v) { written=p; return true; }
}''')
    shutil.copyfile(ROOT/'android/payload/card-counter/EmbeddedPackGate.qml',base/'EmbeddedPackGate.qml')
    (base/'Main.qml').write_text('''import QtQuick
import Fk
Window { width:800; height:400; visible:true
 function status(s) { Backend.status=s;gate.refresh(); }
 EmbeddedPackGate { id:gate; objectName:"gate"; anchors.fill:parent }
}''')
    engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.load(QUrl.fromLocalFile(str(base/'Main.qml')));pump()
    assert engine.rootObjects(),'QML failed to load'
    window=engine.rootObjects()[0];gate=window.findChild(QObject,'gate')
    assert gate.property('checked') and not gate.property('blocked'),'normal APK must load without bundle gate'
    from PySide6.QtCore import Q_ARG
    def status(data):
        QMetaObject.invokeMethod(window,'status',Q_ARG('QVariant',json.dumps(data)));pump()
    status({'required':True,'state':'preparing','title':'TEST','completed':1,'total':3})
    assert gate.property('blocked') and gate.property('visible'),'preparation must block game config loading'
    status({'required':True,'state':'error','title':'TEST'})
    assert gate.property('blocked'),'failed preparation must not silently enter without effects'
    status({'required':True,'state':'ready','completed':3,'total':3})
    assert not gate.property('blocked') and not gate.property('visible'),'ready state releases game loader'
    result={'passed':True,'actualGateQml':True,'absentBundleAllowed':True,'pendingAndErrorBlockGameLoader':True,'readyReleasesGameLoader':True,'phoneTested':False}
    (OUT/'gate-result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
    window.close();engine.deleteLater();pump()
