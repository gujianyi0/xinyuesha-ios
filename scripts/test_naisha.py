"""Actual QML integration: explicit choice, actor/side routing and restoration.

The Spine ABI fixture only tests lifecycle. Native GPU playback is separate.
"""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QTimer,QEventLoop,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg));app=QGuiApplication([])
if Path('C:/Windows/Fonts/msyh.ttc').exists():
    font=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont(QFontDatabase.applicationFontFamilies(font)[0]))
with tempfile.TemporaryDirectory(dir=a.output) as temp:
    folder=Path(temp)
    def put(name,value):
        path=folder/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value,'utf8')
    layer={'atlas':'a/skin.atlas','skeleton':'a/skin.skel','animation':'play','x':[0,.5],'y':[0,.5],'scale':.5,'speed':1}
    rows=[dict(id='skin-main',sourceGeneral='diaochan',character='貂蝉',name='test',title='貂蝉 · test',idle=layer,attack=layer,skill=layer),dict(id='skin-deputy',sourceGeneral='sunshangxiang',character='孙尚香',name='test',title='孙尚香 · test',idle=layer,attack=layer)]
    put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend','Mediator']))
    put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string path:"file:///fixture"}')
    put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property var enabledResourcePacks:["奶杀动皮-v1"];property bool banChangeSkin:false;}')
    put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject{function ev(s){return !s.includes("unknown");}function tr(s){return s==="ol__diaochan"?"貂蝉":s==="shen__diaochan"?"神貂蝉":s;}}')
    put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
    put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool fail:false;property string preferences:"{}";property var catalog:'+json.dumps({'schema':1,'id':'奶杀动皮-v1','skins':rows},ensure_ascii=False)+'''
 function readFileFromAssets(p){return preferences;}function readJsonObjectFromFile(p){return catalog;}
 function writeFileToAssets(p,v){if(fail)return false;preferences=v;return true;}}
''')
    put('Spine/qmldir','module Spine\nSkeletonAnimation 1.0 SkeletonAnimation.qml\nsingleton SpineVersion 1.0 SpineVersion.qml\nsingleton TestControl 1.0 TestControl.qml\n')
    put('Spine/SpineVersion.qml','pragma Singleton\nimport QtQuick\nQtObject{enum Version{Auto}}')
    put('Spine/TestControl.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool fail:false;}')
    put('Spine/SkeletonAnimation.qml','''import QtQuick
Item{id:motion;property url atlasFile;property url skeletonDataFile;property real skeletonScale:1;property real timeScale:1;property int spineVersion:0;property bool premultipliedAlapha:false;property bool loaded:false;property bool playing:false
 signal skeletonLoadFinished(bool ok);signal complete(int trackIndex,int loopCount)
 function clearTracks(){playing=false;}function setToSetupPose(){}function setAttachment(slot,name){}
 function setAnimation(track,name,loop){playing=loaded&&name==="play";if(playing&&!loop)done.restart();}function isPlaying(track){return playing;}
 Timer{interval:15;running:true;onTriggered:{motion.loaded=!TestControl.fail;motion.skeletonLoadFinished(motion.loaded);}}
 Timer{id:done;interval:60;onTriggered:motion.complete(0,1)}
}''')
    for name in ['NaishaSkins.qml','NaishaPortrait.qml','NaishaLayer.qml']:shutil.copyfile(a.payload/'card-counter'/name,folder/name)
    put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import Spine
Window{id:win;width:820;height:520;visible:true
 NaishaSkins{id:manager;owner:owner}
 Item{id:owner;property var currentScene:scene;function generalOwnsSkill(g,name){return name==="skill-main"&&g==="ol__diaochan";}}
 Item{id:scene;anchors.fill:parent;property var dataModel:({players:[{photoItem:photo}]})
  Item{id:photo;width:120;height:180;property int playerid:2;property string general:"ol__diaochan";property string deputyGeneral:"sunshangxiang"
   Item{id:mainArea;width:120;height:180;property var skelData:({});property string general:photo.general;Loader{id:stock;anchors.fill:parent;sourceComponent:Rectangle{color:"red"}}}
   Item{id:deputyArea;x:125;width:120;height:180;property var skelData:({});property string general:photo.deputyGeneral;Loader{id:stockDeputy;anchors.fill:parent;sourceComponent:Rectangle{color:"blue"}}}
  }
 }
 function choose(g,index){return manager.choose(g,manager.catalog[index]);}
 function remove(g){manager.choose(g,null);}
 function event(c,d){Mediator.commandGot(null,c,d);}
 function disable(){Config.enabledResourcePacks=[];}function enable(){Config.enabledResourcePacks=["奶杀动皮-v1"];}
 function ban(value){Config.banChangeSkin=value;}
 function hideScene(){scene.visible=false;}function showScene(){scene.visible=true;}
 function replaceGeneral(){photo.general="shen__diaochan";manager.sync();}
 function failSave(){Backend.fail=true;}function failLoad(){TestControl.fail=true;manager.release();manager.sync();}
 function open(){manager.openSettings();}
 function state(){manager.sync();return JSON.stringify({states:manager.states.map(s=>({general:s.general,action:s.effect.action,ready:s.effect.ready})),stock:stock.opacity,deputy:stockDeputy.opacity,choices:manager.choices,error:manager.error,stored:Backend.preferences});}
}''')
    engine=QQmlApplicationEngine();engine.addImportPath(str(folder));engine.load(QUrl.fromLocalFile(str(folder/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
    def pump(ms=45):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
    def call(name,*args):return QMetaObject.invokeMethod(win,name,Q_RETURN_ARG('QVariant'),*[Q_ARG('QVariant',v) for v in args])
    def action(name,*args):QMetaObject.invokeMethod(win,name,*[Q_ARG('QVariant',v) for v in args]);pump()
    def state():return json.loads(call('state'))
    pump();assert not state()['states'],'Installing a pack must not replace appearances'
    assert not call('choose','shen__diaochan',0);assert not state()['choices'],'Identity mismatch must be rejected'
    assert not call('choose','unknown',0)
    assert call('choose','ol__diaochan',0);pump();s=state();assert len(s['states'])==1 and s['stock']==0 and s['deputy']==1,s
    assert call('choose','sunshangxiang',1);pump();assert len(state()['states'])==2
    action('event','Fk.GuanNingSkinAction',{'player':99,'action':'attack'});assert not any(s['action'] for s in state()['states'])
    action('event','Animate',{'player':2,'type':'InvokeSkill','name':'skill-main'});s=state();assert s['states'][0]['action']=='skill' and s['states'][1]['action']=='',s
    pump(90);assert not any(s['action'] for s in state()['states'])
    action('event','Fk.GuanNingSkinAction',{'player':2,'action':'attack'});assert all(s['action']=='attack' for s in state()['states'])
    pump(90);action('disable');s=state();assert not s['states'] and s['stock']==s['deputy']==1
    action('enable');pump();assert len(state()['states'])==2
    action('hideScene');assert not state()['states'];action('showScene');pump();assert len(state()['states'])==2
    action('ban',True);assert not state()['states'];action('ban',False);pump();assert len(state()['states'])==2
    action('open');pump();win.grabWindow().save(str(a.output/'picker.png'))
    action('remove','sunshangxiang');assert len(state()['states'])==1 and state()['deputy']==1
    before=state()['stored'];action('failSave');assert not call('choose','sunshangxiang',1);assert state()['stored']==before
    action('failLoad');pump();assert state()['stock']==1,'Failed renderer must preserve stock appearance'
    action('replaceGeneral');assert not state()['states']
    bad=[s for s in logs if any(x in s for x in ['TypeError','ReferenceError','is not a function','Binding loop','Unable to assign','Cannot assign'])];assert not bad,bad
    result={'passed':True,'qt':__import__('PySide6').__version__,'explicitSelection':True,'identityMismatchRejected':True,'mainDeputyRouting':True,'restoreOnDisableHideBanLoadFailure':True,'failedSavePreserved':True,'nativeAnimationTest':False}
    (a.output/'result.json').write_text(json.dumps(result,indent=2),'utf8');print(json.dumps(result))
