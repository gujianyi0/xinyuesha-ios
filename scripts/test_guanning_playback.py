"""QML lifecycle with simulated native load/completion; visual proof is a device check."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Basic')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,QTimer,QEventLoop,QPoint,Qt,QObject,qInstallMessageHandler
from PySide6.QtTest import QTest
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
p=argparse.ArgumentParser();p.add_argument('--resources',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
 b=Path(tmp)
 def put(n,s):f=b/n;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(s,encoding='utf8')
 put('Spine/qmldir','module Spine\nSkeletonAnimation 1.0 SkeletonAnimation.qml\nsingleton SpineVersion 1.0 SpineVersion.qml\n')
 put('Spine/SpineVersion.qml','pragma Singleton\nimport QtQuick\nQtObject{enum Version{Auto}}')
 put('Spine/SkeletonAnimation.qml','''import QtQuick
Item{id:root;property url atlasFile;property url skeletonDataFile;property real skeletonScale:1;property int spineVersion:0;property bool premultipliedAlapha:false;property bool loaded:false;property bool playing:false
 signal skeletonLoadFinished(bool ok);signal complete(int trackIndex,int loopCount)
 function clearTracks(){playing=false;clock.stop();}function setToSetupPose(){}
 function setAnimation(track,name,loop){playing=loaded&&["gongji","jineng","play"].includes(name);if(playing&&!loop){clock.interval=name==="gongji"?800:name==="jineng"?1100:100;clock.restart();}}
 function isPlaying(track){return playing;}
 Timer{interval:30;running:true;onTriggered:{root.loaded=true;root.skeletonLoadFinished(true);}}
 Timer{id:clock;onTriggered:{root.playing=false;root.complete(0,1);}}
}''')
 shutil.copytree(a.resources,b/'patch')
 layer=Path(__file__).resolve().parents[1]/'android/payload/card-counter/EffectLayer.qml'
 if layer.exists():shutil.copyfile(layer,b/'EffectLayer.qml')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import "patch" as Patch
Window{id:win;width:1200;height:540;visible:true
 property int gameClicks:0
 Item{id:zeroHeightUi;x:0;y:480;width:1200;height:0
  Button{id:gameControl;x:850;y:0;width:200;height:50;text:"游戏操作";onClicked:win.gameClicks++}
 }
 Item{id:gameScene;anchors.fill:parent;property var dashboard:zeroHeightUi;property var dataModel:({players:[]})
  Item{id:gameActor;x:1020;y:400;width:130;height:120}
 }
 property var preview:null
 Item{id:scaledTable;width:win.width/1.6;height:win.height/1.6;scale:1.6;transformOrigin:Item.TopLeft}
 Component.onCompleted:preview=Qt.createComponent("patch/GuanNingPreview.qml").createObject(scaledTable,{resourceRoot:Qt.resolvedUrl("patch/")})
 function openPreview(){preview.open();}
 function attack(){return preview.actionPlayer.playAction("attack",{targets:[2]});}
 function skill(){return preview.actionPlayer.playAction("skill",{});}
 function invalid(){return preview.actionPlayer.playAction("shown",{});}
 function closePreview(){preview.close();}
 function cancelAction(){preview.actionPlayer.finishAction(preview.actionPlayer.generation,false);}
 function gameState(){return gameClicks;}
 function gameProjectionMode(){preview.actionPlayer.scene=gameScene;preview.actionPlayer.photo=gameActor;}
 function state(){const a=preview.actionPlayer;const surface=a.viewport||a.scene;const cinema=Array.from(surface.children).find(c=>c.objectName==="guanningCinematicBackdrop");return JSON.stringify({ready:a.ready,active:a.activeAction,started:a.startedCount,completed:a.completedCount,error:a.lastError,originalOpacity:a.stockArea.opacity,overlayWidth:preview.parent.width,overlayHeight:preview.parent.height,previewWidth:preview.width,previewHeight:preview.height,edition:a.edition||"v1",cinematicOpacity:cinema?cinema.opacity:0,cinematicWidth:cinema?cinema.width:0,cinematicHeight:cinema?cinema.height:0,protectsUi:a.protectedUi!==undefined,projectedUiCount:a.protectedUi?a.protectedUi.length:0});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump(ms):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def call(n):return QMetaObject.invokeMethod(win,n,Q_RETURN_ARG('QVariant'))
 def state():return json.loads(call('state'))
 def until(predicate):
  for _ in range(150):
   pump(20)
   if predicate():return
  raise AssertionError((state(),logs))
 QMetaObject.invokeMethod(win,'openPreview');call('attack')
 for _ in range(200):
  pump(10)
  if state()['ready'] and state()['active']=='attack':break
 assert state()['ready'] and state()['active']=='attack', (state(),logs)
 assert state()['overlayWidth']==1200 and state()['overlayHeight']==540,(state(),logs)
 assert state()['previewWidth']<=1200 and state()['previewHeight']<=540,state()
 assert state()['cinematicOpacity']==0,state()
 assert state()['originalOpacity']==0,state();until(lambda:not state()['active']);assert state()['completed']==1 and state()['originalOpacity']==1,state()
 call('attack');pump(60);call('skill');pump(60);assert state()['active']=='skill',state()
 if state()['edition']=='v2':
  until(lambda:state()['cinematicOpacity']>.80)
  assert state()['cinematicWidth']==1200 and state()['cinematicHeight']==540,state()
 call('attack');assert state()['active']=='skill',state();until(lambda:not state()['active']);assert state()['completed']==2,state()
 before=state()['started'];assert call('invalid') is False;assert state()['started']==before,state()
 call('attack');pump(100);QMetaObject.invokeMethod(win,'closePreview');pump(350);assert not state()['active'] and state()['completed']==2,state()
 assert state()['cinematicOpacity']==0,state()
 if state()['edition']=='v2' and state()['protectsUi']:
  call('gameProjectionMode');call('skill');until(lambda:state()['cinematicOpacity']>.80)
  assert state()['projectedUiCount']==1,state()
  QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(950,505));pump(20)
  assert call('gameState')==1,'Full-screen visual layer swallowed the game control click'
  dismiss=win.findChild(QObject,'guanningDismissEffect');assert dismiss is not None
  x=dismiss.property('x')+dismiss.property('width')*.5;y=dismiss.property('y')+dismiss.property('height')*.5
  QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(int(x),int(y)))
  until(lambda:not state()['active'] and state()['cinematicOpacity']==0)
 errors=[m for m in logs if any(t in m for t in ['TypeError','ReferenceError','SyntaxError','Cannot assign','Unable to assign','Binding loop'])];assert not errors,errors
 result={'passed':True,'previewFitsScaledTable':True,'loadingQueue':True,'completionRestoresPortrait':True,'skillPriority':True,'staleCompletionIgnored':True,'closingCancels':True,'invalidActionRejected':True,'nativeLoadAndCompletion':'simulated','visualAnimationTested':False,'qt':__import__('PySide6').__version__}
 if state()['edition']=='v2':result.update(originalFullscreenArtworkRetained=True,fullApplicationWindowDimensionsVerified=True)
 if state()['edition']=='v2' and state()['protectsUi']:result.update(gameControlsClickableDuringSkill=True,gameUiProjectedAboveEffect=True,dismissEffectRestoresUi=True)
 (a.work_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(result));win.close()
