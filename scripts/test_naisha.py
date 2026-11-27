"""Actual QML integration: explicit choice, actor/side routing and restoration.

The Spine ABI fixture only tests lifecycle. Native GPU playback is separate.
"""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QTimer,QEventLoop,qInstallMessageHandler,QPointF
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow,QQuickItem
from PySide6.QtTest import QTest
from PySide6.QtCore import Qt
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
    put('Fk/Lua.qml',r'''pragma Singleton
import QtQuick
QtObject{
 function ev(s){
  if(s.includes("table.sort"))return ["diaochan","ol__diaochan","jie__diaochan","shen__diaochan","sunshangxiang"];
  const match=s.match(/Fk.generals\[("[^"]+")\]/);if(!match)return null;
  const name=JSON.parse(match[1]);if(name==="unknown")return null;
  const divine=name==="shen__diaochan",base=name.split("__").pop();
  const label=base==="diaochan"?"貂蝉":base==="sunshangxiang"?"孙尚香":base;
  return {name:name,trueName:base,kingdom:divine?"god":"qun",base:label,label:(divine?"神":name.startsWith("jie__")?"界":"")+label};
 }
 function tr(s){return s==="ol__diaochan"?"貂蝉":s==="shen__diaochan"?"神貂蝉":s;}
}''')
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
Window{id:win;width:820;height:520;visible:true;property bool stockWanted:true
 NaishaSkins{id:manager;owner:owner}
 Item{id:owner;property var currentScene:scene;function generalOwnsSkill(g,name){return name==="skill-main"&&g==="ol__diaochan";}}
 Item{id:scene;anchors.fill:parent;property var dataModel:({players:[{photoItem:photo}]})
  Item{id:photo;width:240;height:180;property int playerid:2;property string general:"ol__diaochan";property string deputyGeneral:"sunshangxiang"
   property alias photoMask:maskShape
   Item{id:mainArea;width:120;height:180;property var skelData:({});property string general:photo.general;Loader{id:stock;anchors.fill:parent;active:win.stockWanted;sourceComponent:Rectangle{color:"red"}}}
   Item{id:deputyArea;x:125;width:120;height:180;property var skelData:({});property string general:photo.deputyGeneral;Loader{id:stockDeputy;anchors.fill:parent;sourceComponent:Rectangle{color:"blue"}}}
   Item{id:maskShape;width:240;height:180;visible:false}
   Item{id:maskSurface;anchors.fill:maskShape;property var maskSource:maskShape}
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
 function close(){for(const p of win.contentItem.children)if(p.close)p.close();}
 function savedReload(){manager.readChoices();manager.reload();}
 function variant(g){photo.general=g;manager.sync();}
 function stockState(){return JSON.stringify({mainActive:stock.active,mainItem:!!stock.item,deputyActive:stockDeputy.active,deputyItem:!!stockDeputy.item});}
 function maskedSlots(){return manager.states.length===2 && manager.states.every(s=>s.slot.parent===maskSurface && s.slot.width===120 && s.slot.height===180 && s.slot.x===(s.general===photo.deputyGeneral?120:0));}
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
    assert call('choose','diaochan',0);pump();s=state();assert len(s['states'])==1 and s['stock']==0 and s['deputy']==1,s
    action('variant','jie__diaochan');pump();assert state()['states'][0]['general']=='jie__diaochan','Tagged translations must match the engine identity'
    action('remove','jie__diaochan');assert not state()['states'],'Explicit restoration must override family inheritance'
    action('variant','ol__diaochan');pump();assert len(state()['states'])==1
    action('savedReload');pump();assert len(state()['states'])==1,'Saved choices must survive reopening/reloading'
    stock=json.loads(call('stockState'));assert not stock['mainActive'] and not stock['mainItem'] and stock['deputyActive'] and stock['deputyItem'],stock
    assert call('choose','sunshangxiang',1);pump();assert len(state()['states'])==2
    assert call('maskedSlots'),'Main/deputy skeletons must attach to the visible mask surface, within their own half'
    action('event','Fk.GuanNingSkinAction',{'player':99,'action':'attack'});assert not any(s['action'] for s in state()['states'])
    action('event','Animate',{'player':2,'type':'InvokeSkill','name':'skill-main'});s=state();assert s['states'][0]['action']=='skill' and s['states'][1]['action']=='',s
    pump(90);assert not any(s['action'] for s in state()['states'])
    action('event','Fk.GuanNingSkinAction',{'player':2,'action':'attack'});assert all(s['action']=='attack' for s in state()['states'])
    pump(90);action('disable');s=state();assert not s['states'] and s['stock']==s['deputy']==1
    stock=json.loads(call('stockState'));assert stock['mainActive'] and stock['mainItem'] and stock['deputyActive'] and stock['deputyItem'],stock
    win.setProperty('stockWanted',False);pump();assert not json.loads(call('stockState'))['mainItem'],'Original dynamic active binding must be restored'
    win.setProperty('stockWanted',True);pump();assert json.loads(call('stockState'))['mainItem']
    action('enable');pump();assert len(state()['states'])==2
    action('hideScene');assert not state()['states'];action('showScene');pump();assert len(state()['states'])==2
    action('ban',True);assert not state()['states'];action('ban',False);pump();assert len(state()['states'])==2
    button=win.findChild(QQuickItem,'naishaInGameSkinButton');assert button and button.isVisible()
    pos=button.mapToScene(QPointF(button.width()/2,button.height()/2))
    QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,pos.toPoint());pump()
    apply=win.findChild(QQuickItem,'naishaApplySkin');assert apply and apply.isVisible(),'Actual in-game action must open the picker'
    target=win.findChild(QQuickItem,'naishaGeneralChoice');assert target and target.property('count')==1
    win.grabWindow().save(str(a.output/'picker.png'))
    # A landscape phone has substantially less logical height than a desktop.
    # The preview must stay inside the window and all actions must be reachable
    # by scrolling, rather than overflowing below the modal.
    win.setWidth(660);win.setHeight(300);pump(150)
    preview=win.findChild(QQuickItem,'naishaPortraitPreview')
    scroll=win.findChild(QQuickItem,'naishaControlsScroll')
    assert preview and scroll
    for item in [preview,scroll]:
        pos=item.mapToScene(QPointF(0,0))
        assert pos.y()>=0 and pos.y()+item.height()<=win.height()+1,(item.objectName(),pos,item.height())
    flick=scroll.property('contentItem')
    assert flick.property('contentHeight')>flick.height(),'Phone controls must be scrollable'
    flick.setProperty('contentY',max(0,flick.property('contentHeight')-flick.height()));pump()
    win.grabWindow().save(str(a.output/'picker-phone-scrolled.png'))
    win.setWidth(820);win.setHeight(520);pump()
    action('remove','sunshangxiang');assert len(state()['states'])==1 and state()['deputy']==1
    before=state()['stored'];action('failSave');assert not call('choose','sunshangxiang',1);assert state()['stored']==before
    action('failLoad');pump();assert state()['stock']==1,'Failed renderer must preserve stock appearance'
    assert json.loads(call('stockState'))['mainActive'] and json.loads(call('stockState'))['mainItem'],'Load failure must restore the stock renderer'
    action('replaceGeneral');assert not state()['states']
    bad=[s for s in logs if any(x in s for x in ['TypeError','ReferenceError','is not a function','Binding loop','Unable to assign','Cannot assign'])];assert not bad,bad
    result={'passed':True,'qt':__import__('PySide6').__version__,'explicitSelection':True,'sameIdentityVariantsAndTaggedTranslation':True,'savedChoiceReload':True,'explicitRestoreOverridesFamily':True,'identityMismatchRejected':True,'mainDeputyRouting':True,'visibleMaskSurfaceAndSplitSlots':True,'landscapePhoneScrollAndPreviewBounds':True,'restoreOnDisableHideBanLoadFailure':True,'replacedStockRendererActuallyUnloaded':True,'originalActiveBindingRestored':True,'failedSavePreserved':True,'nativeAnimationTest':False}
    (a.output/'result.json').write_text(json.dumps(result,indent=2),'utf8');print(json.dumps(result))
