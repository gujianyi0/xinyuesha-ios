"""Real Quick Popup paint order, hit testing, transform and surface lifetime."""
import json, os, shutil, tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QUrl, QTimer, QEventLoop, QMetaObject, Q_RETURN_ARG, Qt, QPoint, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'work/three-fixes-20261126/layer'
OUT.mkdir(parents=True, exist_ok=True)
app = QGuiApplication([])
logs = []
qInstallMessageHandler(lambda kind, context, message: logs.append(message))
with tempfile.TemporaryDirectory(dir=OUT) as temporary:
    folder = Path(temporary)
    shutil.copy(ROOT/'android/payload/card-counter/EffectLayer.qml', folder)
    (folder/'Main.qml').write_text('''import QtQuick
import QtQuick.Controls
Window {
 id:win;width:600;height:400;visible:true
 property int dialogClicks:0;property int tableClicks:0
 Button{x:130;y:95;width:120;height:50;text:"table";onClicked:win.tableClicks++}
 Button{x:470;y:320;width:120;height:50;text:"outside";onClicked:win.tableClicks++}
 Item{id:viewport;x:40;y:30;scale:0.75;transformOrigin:Item.TopLeft
  Item{id:stage;x:100;y:60;width:400;height:200
   EffectLayer{sourceItem:stage;objectName:"testSurface";clip:true
    Rectangle{anchors.fill:parent;color:"#d02020"}
   }
  }
 }
 Popup{id:dialog;x:0;y:0;width:600;height:400;modal:true;padding:0
  background:Rectangle{color:"#003399"}
  contentItem:Item{Button{x:130;y:95;width:120;height:50;text:"dialog";onClicked:win.dialogClicks++}}
 }
 function openDialog(){dialog.open();}
 function closeDialog(){dialog.close();}
 function moveStage(){viewport.scale=0.5;viewport.x=60;stage.x=80;}
 function hideStage(){stage.visible=false;}
 function destroyStage(){stage.destroy();}
 function surfaceCount(){return win.Overlay.overlay.children.filter(c=>c.objectName==="testSurface").length;}
}''', encoding='utf8')
    engine = QQmlApplicationEngine()
    engine.load(QUrl.fromLocalFile(str(folder/'Main.qml')))
    assert engine.rootObjects(), logs
    win = engine.rootObjects()[0]
    def pump(ms=160):
        loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
    def call(name):
        QMetaObject.invokeMethod(win,name);pump()
    def click(x,y):
        QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(x,y));pump()
    pump();assert win.grabWindow().pixelColor(150,110).name()=='#d02020',logs
    call('openDialog')
    assert win.grabWindow().pixelColor(150,110).name()=='#d02020', logs
    click(190,120);assert win.property('dialogClicks')==1
    click(520,345);assert win.property('tableClicks')==0, 'Modal input isolation lost'
    assert win.grabWindow().save(str(OUT/'animation-above-quick-popup.png'))
    call('closeDialog');assert win.grabWindow().pixelColor(150,110).name()=='#d02020'
    click(190,120);assert win.property('tableClicks')==1
    call('moveStage');assert win.grabWindow().pixelColor(110,80).name()=='#d02020'
    assert win.grabWindow().pixelColor(380,180).name()!='#d02020', 'Old transform retained'
    call('hideStage');assert win.grabWindow().pixelColor(110,80).name()!='#d02020'
    call('destroyStage')
    count=QMetaObject.invokeMethod(win,'surfaceCount',Q_RETURN_ARG('QVariant'))
    assert count==0, ('Reparented surface leaked',count)
    errors=[m for m in logs if any(t in m for t in ('TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop'))]
    assert not errors,errors
    report={'passed':True,'actualQuickPopupCovered':True,'dialogButtonClickableUnderArt':True,
            'modalBlocksBackground':True,'tableButtonClickableUnderArt':True,
            'viewportTransformUpdated':True,'hiddenAndDestroyedSurfaceCleaned':True,'phoneUsed':False}
    (OUT/'result.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print(json.dumps(report));win.close()
