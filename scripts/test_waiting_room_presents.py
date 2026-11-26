"""Waiting-room gift adapter with original avatar panel/handler; no live Chat."""
import argparse,json,os,shutil,tempfile,time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,QPoint,QPointF,Qt,QEventLoop,QTimer,QEvent,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);p.add_argument('--os',choices=['Android','iOS'],default='Android');a=p.parse_args()
a.work_dir.mkdir(parents=True,exist_ok=True);root=Path(__file__).resolve().parents[1]
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
font=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont(QFontDatabase.applicationFontFamilies(font)[0]))
with tempfile.TemporaryDirectory(dir=a.work_dir) as directory:
    base=Path(directory)
    def put(n,s):
        path=base/n;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(s,encoding='utf8')
    put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua','Backend','Mediator','SkinBank']))
    put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property var self:({id:1});property string os:'+json.dumps(a.os)+';property string path:"/fixture";function notifyServer(c,d){}}')
    put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool replaying:false;property bool observing:false;property bool banChangeSkin:false;property var enabledResourcePacks:[];property var blockedUsers:[];property string roomBg:"";property string lobbyBg:"";property real winScale:1;}')
    put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject{property var selfPlayer:({id:1});function tr(s){return s;}function ev(s){return true;}function getCompNum(){return {minComp:0,curComp:3};}}')
    put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{function readFileFromAssets(p){return "{}";}function writeFileToAssets(p,v){return true;}}')
    put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{property int chats:0;signal commandGot(var sender,string command,var data);function notify(sender,command,data){if(command==="IWantToChat")chats++;commandGot(sender,command,data);}}')
    put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject{property string pixAnimDir:"/fixture";}')
    put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
    put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject{property var roomScene:null;}')
    # The host imports the native target-line player, even in a waiting room.
    # Native rendering is covered separately; this fixture only supplies its ABI.
    put('Spine/qmldir','module Spine\nSkeletonAnimation 1.0 SkeletonAnimation.qml\nsingleton SpineVersion 1.0 SpineVersion.qml\n')
    put('Spine/SpineVersion.qml','pragma Singleton\nimport QtQuick\nQtObject{enum Version{Auto}}')
    put('Spine/SkeletonAnimation.qml','''import QtQuick
Item{property url atlasFile;property url skeletonDataFile;property real skeletonScale:1;property real timeScale:1
 property int spineVersion:0;property bool premultipliedAlapha:false;property bool loaded:false
 signal skeletonLoadFinished(bool ok);signal complete(int trackIndex,int loopCount)
 function clearTracks(){} function setToSetupPose(){} function setAnimation(track,name,loop){} function isPlaying(track){return false;}}
''')
    for module,file in [('Fk/Widgets','TapHandler'),('Fk/Components/GameCommon','BasicItem'),('Fk/Components/WaitingRoom','WButton')]:
        put(module+'/qmldir','module '+module.replace('/','.')+'\n'+file+' 1.0 '+file+'.qml\n')
        shutil.copyfile(root/'runtime'/module/(file+'.qml'),base/module/(file+'.qml'))
    stock=(root/'runtime/Fk/Components/WaitingRoom/AvatarCardItem.qml').read_text(encoding='utf8')
    panel=stock[stock.index('  Rectangle {\n    id: panel'):stock.index('  onClicked: {',stock.index('    function close()'))]
    put('AvatarFixture.qml','''import QtQuick
import Fk
import Fk.Components.WaitingRoom
Item {id:root;required property var roomScene;property bool hasPlayer:true;property int playerid:2;property string screenName:"Other";width:170;height:115
 PANEL
 function open(){roomScene.areaHandler.show(panel);}
}'''.replace('PANEL',panel))
    stock=(root/'runtime/Fk/Pages/Common/WaitingRoom.qml').read_text(encoding='utf8')
    handler=stock[stock.index('  MouseArea {\n    id: globalTapHandler'):stock.index('  // 弹幕')]
    shutil.copytree(a.payload/'card-counter',base/'card-counter')
    put('Main.qml','''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import "card-counter" as Counter
Window {id:win;width:800;height:500;visible:true;property var sent:[];property bool switchDuringSend:false
 property alias selfObject:self;QtObject{id:self;property int id:1}
 QtObject{id:endpoint;function notifyServer(c,d){win.sent=win.sent.concat([{command:c,data:d}]);if(win.switchDuringSend){win.switchDuringSend=false;win.startGame();}}}
 Counter.CounterHost{id:counter;navigationRoot:navigation;clientContext:endpoint}
 Item{id:navigation;anchors.fill:parent
  Item{id:stack;property var currentItem:roomPage;property int depth:1;function get(i){return currentItem;}}
  Item{id:roomPage;anchors.fill:parent;property var gameContent:roomScene}
  Item{id:lobby}
  Item{id:roomScene;anchors.fill:parent;visible:stack.currentItem===roomPage&&roomPage.gameContent===roomScene
   property bool isAllReady:false;property bool isOwner:false;property int playerNum:8
   property alias photoModel:seats;property alias areaHandler:globalTapHandler
   function givePresent(k,id){endpoint.notifyServer("Chat",{type:2,msg:"$@"+k+":"+id});}
   function sendDanmu(s){}
   ListModel{id:seats;Component.onCompleted:{for(const row of [{id:1,screenName:"Self",sealed:false},{id:2,screenName:"Other",sealed:false},{id:-2,screenName:"Bot",sealed:false},{id:-1,screenName:"",sealed:false},{id:0,screenName:"Invalid",sealed:false},{id:6,screenName:"Sealed",sealed:true},{id:2,screenName:"Duplicate",sealed:false},{id:7,screenName:"",sealed:false}])append(row);}}
   AvatarFixture{id:avatar;x:100;y:80;roomScene:roomScene}
   HANDLER
  }
  Item{id:battle;anchors.fill:parent;visible:roomPage.gameContent===battle;property var dataModel:({players:[{playerid:1},{playerid:3}]})}
 }
 function open(){avatar.open();}
 function single(){const panel=globalTapHandler.tmpItem;const flow=panel.children.find(c=>c.children&&Array.from(c.children).some(b=>b.text==="Give Flower"));flow.children.find(b=>b.text==="Give Flower").clicked(null);}
 function resetSent(){sent=[];}
 function startGame(){globalTapHandler.closeItem();roomPage.gameContent=battle;counter.currentScene=battle;}
 function returnWaiting(){counter.currentScene=null;roomPage.gameContent=roomScene;}
 function addPlayer(){seats.append({id:9,screenName:"New",sealed:false});roomScene.playerNum++;}
 function switchOnSend(){switchDuringSend=true;}
 function leave(){stack.currentItem=lobby;}
 function narrow(){win.width=340;avatar.x=20;}
 function state(){const bar=counter.waitingPresentBar;return JSON.stringify({chats:Mediator.chats,waitingShortcuts:roomScene.children.filter(c=>c.objectName==="roomBackgroundChatShortcut").length,sent:sent,rest:counter.presentRestSeconds,bar:bar?{visible:bar.visible,x:bar.x,y:bar.y,width:bar.width,height:bar.height}:null,panelOpen:globalTapHandler.visible,context:counter.presentScene===roomScene?"waiting":counter.presentScene===battle?"battle":"none"});}
}'''.replace('HANDLER',handler))
    engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.rootContext().setContextProperty('ClientInstance',None);engine.rootContext().setContextProperty('Self',None)
    engine.load(QUrl.fromLocalFile(str(base/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
    engine.rootContext().setContextProperty('Self',win.property('selfObject'))
    def pump(ms=100):
        loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec();app.sendPostedEvents(None,QEvent.DeferredDelete)
    def call(n):QMetaObject.invokeMethod(win,n);pump(300)
    def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
    def point(item):
        p=item.mapToScene(QPointF(item.width()/2,item.height()/2));return QPoint(round(p.x()),round(p.y()))
    def click(name):QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,point(win.findChild(QObject,name)));pump()
    def cooldown():
        deadline=time.monotonic()+12
        while state()['rest'] and time.monotonic()<deadline:pump(150)
        assert state()['rest']==0
    pump(300);assert state()['context']=='waiting' and not state()['sent'] and not state()['bar']['visible'],(state(),logs)
    assert state()['waitingShortcuts']==1,state()
    touch=QTest.createTouchDevice();blank=QPoint(650,230)
    def tap():
        QTest.touchEvent(win,touch).press(0,blank,win).commit();pump(30)
        QTest.touchEvent(win,touch).release(0,blank,win).commit();pump(55)
    tap();tap();assert state()['chats']==1,state()
    pump(600);QTest.mouseDClick(win,Qt.LeftButton,Qt.NoModifier,blank);QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,blank);pump();assert state()['chats']==2,state()
    pump(600);QTest.touchEvent(win,touch).press(0,blank,win).commit();pump(1050)
    QTest.touchEvent(win,touch).release(0,blank,win).commit();pump();assert state()['chats']==3,state()
    pump(600);QTest.touchEvent(win,touch).press(0,blank,win).commit();pump(30)
    QTest.touchEvent(win,touch).move(0,QPoint(700,300),win).commit();pump(1000)
    QTest.touchEvent(win,touch).release(0,QPoint(700,300),win).commit();pump();assert state()['chats']==3,state()
    call('open');assert state()['bar']['visible'];win.grabWindow().save(str(a.work_dir/'waiting-room-actions.png'))
    tap();tap();assert state()['chats']==3,'Avatar popup must retain input'
    call('open')
    egg=win.findChild(QObject,'waitingRoomEggButton');assert egg
    QTest.mousePress(win,Qt.LeftButton,Qt.NoModifier,point(egg));pump(1300);assert not state()['sent']
    QTest.mouseRelease(win,Qt.LeftButton,Qt.NoModifier,point(egg));pump();assert [r['data']['msg'] for r in state()['sent']]==['$@Egg:2','$@Egg:-2'],(state(),logs)
    assert not state()['panelOpen'];call('startGame');assert state()['rest']>0 and state()['context']=='battle'
    call('returnWaiting');call('open');assert not win.findChild(QObject,'waitingRoomFlowerButton').property('enabled')
    call('addPlayer');cooldown();call('resetSent');click('waitingRoomFlowerButton')
    assert [r['data']['msg'] for r in state()['sent']]==['$@Flower:1','$@Flower:2','$@Flower:-2','$@Flower:9'],state()
    call('open');call('resetSent');call('single');assert [r['data']['msg'] for r in state()['sent']]==['$@Flower:2'],(state(),logs)
    cooldown();call('open');call('narrow');pump();s=state();bar=s['bar'];assert bar['x']>=0 and bar['x']+bar['width']<=win.width() and bar['y']>=0 and bar['y']+bar['height']<=win.height(),s
    win.grabWindow().save(str(a.work_dir/'waiting-room-actions-narrow.png'))
    call('resetSent');call('switchOnSend');click('waitingRoomFlowerButton');assert len(state()['sent'])==1 and state()['context']=='battle',state()
    call('leave');assert not state()['sent'][0]['data']['msg'].endswith(':9')
    errors=[m for m in logs if any(s in m for s in ['TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop','is not a type'])]
    assert not errors,errors
    result={'passed':True,'osFixture':a.os,'actualStockAvatarPanelAndHandler':True,'noIdleSends':True,'seatsFilteredAndDeduplicated':True,'botsSupported':True,'eggsExcludeSelf':True,'flowersIncludeSelf':True,'holdDoesNotRepeat':True,'sharedCooldownAcrossGameStart':True,'newPlayerIncludedOnNextClick':True,'originalSingleGiftPreserved':True,'exitDuringSendStopsRemainder':True,'narrowLayoutWithinScene':True,'liveServerMessagesSent':0}
    (a.work_dir/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8');print(json.dumps(result));win.close()
