"""Actual QML haptic gating, settings merge, native IME action and line geometry."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QObject,Property,Slot,QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QEventLoop,QTimer,Qt,QCoreApplication,QPointF,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QInputMethodEvent,QInputMethodQueryEvent,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1];logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
if Path('C:/Windows/Fonts/msyh.ttc').exists():
    font=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont(QFontDatabase.applicationFontFamilies(font)[0]))
class SelfObject(QObject):
    @Property(int,constant=True)
    def id(self):return 2
class Endpoint(QObject):
    def __init__(self):super().__init__();self.messages=[]
    @Slot(str,'QVariant')
    def notifyServer(self,command,data):self.messages.append((command,data.toVariant() if hasattr(data,'toVariant') else data))
endpoint=Endpoint();self_object=SelfObject()
with tempfile.TemporaryDirectory(dir=a.output) as temp:
    folder=Path(temp)
    def put(name,data):
        path=folder/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(data,encoding='utf8')
    put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Backend','Mediator']))
    put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"iOS";}')
    put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool observing:false;property bool replaying:false;}')
    put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
    put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject{property string stored:'{"directionalLuck":false,"future":7}';property bool failWrite:false;property var haptics:[]
 function readFileFromAssets(path){return stored;}
 function writeFileToAssets(path,value){if(failWrite)return false;stored=value;return true;}
 function playGameHaptic(kind){haptics=haptics.concat([kind]);return true;}}
''')
    shutil.copyfile(a.payload/'card-counter/FeedbackFeatures.qml',folder/'FeedbackFeatures.qml')
    # Use the stock editor's complete signal handler, not a second send implementation.
    text=(root/'runtime/packages/freekill-core/Fk/Components/Common/ChatBox.qml').read_text(encoding='utf8')
    start=text.index('        TextInput {');pos=start+text[start:].index('{');depth=1;end=pos+1
    while depth:
        depth+=int(text[end]=='{')-int(text[end]=='}');end+=1
    editor=text[start:end].replace('id: chatEdit','id: chatEdit;objectName:"realStockChatEditor"')
    put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
Window{id:win;width:800;height:500;visible:true
 property bool isLobby:false
 FeedbackFeatures{id:features;owner:owner;objectName:"feedbackFixture"}
 Item{id:owner;property var currentScene:scene;property var clientContext:ClientInstance}
 Item{id:scene;anchors.fill:parent;property alias dashboard:dash;property var callbacks:({});property int otherAnimations:0
  Item{id:dash;x:100;y:300;width:700;height:200}
  Item{id:ownPortrait;x:650;y:350;width:120;height:145}
  Item{id:other;x:80;y:100;width:100;height:140}
  function getPhoto(id){return id===2?ownPortrait:id===3?other:null;}
  function getPhotoOrDashboard(id){return id===2?dash:getPhoto(id);}
  function addCallback(command,callback){callbacks[command]=callback;}
  function doAnimate(sender,data){otherAnimations++;}
 }
 Item{id:chat;x:10;y:10;width:300;height:50; EDITOR }
 function adapt(){features.adaptChat(chat);features.attachIndications();}
 function enable(){features.setHapticsEnabled(true);}
 function disable(){features.setHapticsEnabled(false);}
 function badSettings(){Backend.stored="invalid";features.setHapticsEnabled(true);}
 function failedSave(){Backend.failWrite=true;features.setHapticsEnabled(false);}
 function restoreSettings(){Backend.failWrite=false;Backend.stored='{"directionalLuck":false,"future":7,"haptics":true}';}
 function event(command,data){Mediator.commandGot(null,command,data);}
 function observe(value){Config.observing=value;}
 function replay(value){Config.replaying=value;}
 function hideScene(){scene.visible=false;}function showScene(){scene.visible=true;}
 function hideApp(){win.hide();}function showApp(){win.show();win.requestActivate();}
 function detach(){owner.clientContext=null;}function attach(){owner.clientContext=ClientInstance;}
 function desktop(){Cpp.os="Windows";}function mobile(){Cpp.os="iOS";}
 Item{id:profile;x:20;y:60;width:760;height:430;visible:false
  Rectangle{anchors.fill:parent;color:"white"}
  Item{property var model:ListModel{ListElement{name:"Userinfo Settings"}ListElement{name:"BG Settings"}ListElement{name:"Audio Settings"}ListElement{name:"Control Settings"}ListElement{name:"UI settings"}}}
  SwipeView{id:profilePages;anchors.fill:parent;Item{}Item{}Item{}Item{}Item{}}
 }
 function adaptProfile(){features.adaptProfile(profile);}
 function profileTabs(){return profile.children.find(c=>"model" in c).model.count;}
 function showProfile(){profilePages.currentIndex=5;profile.visible=true;}
 function hideProfile(){profile.visible=false;}
 function editorFocus(){chatEdit.forceActiveFocus();}
 function points(){const from=features.indicationPoint(scene,2),to=features.indicationPoint(scene,3);return JSON.stringify({from:[from.x,from.y],to:[to.x,to.y],missing:features.indicationPoint(scene,99)});}
 function draw(from,to){scene.callbacks.Animate(null,{type:"Indicate",from:from,to:to});}
 function otherAnimation(){scene.callbacks.Animate(null,{type:"Emotion",player:2});}
 function state(){return JSON.stringify({haptics:Backend.haptics,enabled:features.hapticsEnabled,settings:Backend.stored,error:features.settingsError,active:win.active,enterKey:chatEdit.EnterKey.type,sendKey:Qt.EnterKeySend,otherAnimations:scene.otherAnimations,lines:scene.children.filter(c=>c.objectName==="stockLineFixture").map(c=>({from:[c.start.x,c.start.y],to:c.end.map(p=>[p.x,p.y])}))});}
}'''.replace('EDITOR',editor))
    put('LunarLtk/Components/qmldir','module LunarLtk.Components\nIndicatorLine 1.0 IndicatorLine.qml\n')
    put('LunarLtk/Components/IndicatorLine.qml','import QtQuick\nItem{objectName:"stockLineFixture";property point start;property var end:[];property color color;property bool running:false;signal finished()}')
    engine=QQmlApplicationEngine();engine.addImportPath(str(folder));engine.rootContext().setContextProperty('Self',self_object);engine.rootContext().setContextProperty('ClientInstance',endpoint)
    engine.load(QUrl.fromLocalFile(str(folder/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
    def pump(ms=35):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
    def call(name,*args):
        QMetaObject.invokeMethod(win,name,*[Q_ARG('QVariant',v) for v in args]);pump()
    def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
    def event(command,data):call('event',command,data)
    pump(120);win.requestActivate();pump();call('adapt');assert state()['active'],state()
    event('LogEvent',{'type':'Damage','to':2,'damageNum':1});assert not state()['haptics']
    call('enable');prefs=json.loads(state()['settings']);assert prefs=={'directionalLuck':False,'future':7,'haptics':True},prefs
    event('LogEvent',{'type':'Damage','to':3,'damageNum':1});event('LogEvent',{'type':'Damage','to':2,'damageNum':0});assert not state()['haptics']
    event('LogEvent',{'type':'Damage','to':2,'damageNum':1});event('LogEvent',{'type':'Damage','to':2,'damageNum':1});assert state()['haptics']==['damage'],state()
    event('LogEvent',{'type':'LoseHP'});event('Fk.GameHaptic',{'player':2,'kind':'lose-hp'});event('Fk.GameHaptic',{'player':2,'kind':'turn'})
    assert state()['haptics']==['damage','lose-hp','turn'],state()
    for mode in ['observe','replay']:
        call(mode,True);pump(120);event('Fk.GameHaptic',{'player':2,'kind':'turn'});assert len(state()['haptics'])==3;call(mode,False)
    for off,on in [('hideScene','showScene'),('hideApp','showApp'),('detach','attach')]:
        call(off);pump(120);event('Fk.GameHaptic',{'player':2,'kind':'turn'});assert len(state()['haptics'])==3;call(on)
    call('desktop');pump(120);event('Fk.GameHaptic',{'player':2,'kind':'turn'});assert len(state()['haptics'])==3;call('mobile')
    event('GameOver',{});pump(120);event('Fk.GameHaptic',{'player':2,'kind':'turn'});assert len(state()['haptics'])==3;event('StartGame',{})
    call('desktop');call('adaptProfile');assert QMetaObject.invokeMethod(win,'profileTabs',Q_RETURN_ARG('QVariant'))==5
    call('mobile');call('adaptProfile');call('adaptProfile');assert QMetaObject.invokeMethod(win,'profileTabs',Q_RETURN_ARG('QVariant'))==6
    call('showProfile');control=win.findChild(QObject,'gameHapticsSwitch');assert control
    for _ in range(100):
        pump(20);origin=control.mapToScene(QPointF(0,0))
        if 20<=origin.x()<=21:break
    assert 20<=origin.x() and origin.x()+control.width()<=780 and 60<=origin.y() and origin.y()+control.height()<=490,(origin,control.width(),control.height())
    assert win.grabWindow().save(str(a.output/'function-settings.png'));call('hideProfile')
    call('failedSave');assert state()['enabled'] and state()['error'];call('restoreSettings');call('badSettings');assert state()['settings']=='invalid' and state()['error'];call('restoreSettings')
    assert state()['enterKey']==state()['sendKey'],state();call('editorFocus')
    editor_item=win.findChild(QObject,'realStockChatEditor');commit=QInputMethodEvent();commit.setCommitString('你好，测试');QCoreApplication.sendEvent(editor_item,commit)
    query=QInputMethodQueryEvent(Qt.ImEnterKeyType);QCoreApplication.sendEvent(editor_item,query);assert int(query.value(Qt.ImEnterKeyType))==state()['sendKey']
    QTest.keyClick(win,Qt.Key_Return);pump();assert endpoint.messages==[('Chat',{'type':2,'msg':'你好，测试'})],endpoint.messages
    QTest.keyClick(win,Qt.Key_Return);pump();assert len(endpoint.messages)==1,'Empty send or duplicate handler'
    points=json.loads(QMetaObject.invokeMethod(win,'points',Q_RETURN_ARG('QVariant')));assert points=={'from':[400,400],'to':[130,170],'missing':None},points
    call('draw',2,[[3,99,2]]);call('draw',3,[[2]]);lines=state()['lines'];assert lines and lines[0]=={'from':[400,400],'to':[[130,170]]} and lines[-1]=={'from':[130,170],'to':[[400,400]]},(lines,logs)
    call('otherAnimation');assert state()['otherAnimations']==1
    errors=[s for s in logs if any(t in s for t in ('TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop'))];assert not errors,errors
    result={'passed':True,'payload':str(a.payload),'qt':__import__('PySide6').__version__,'hapticMotorSimulated':True,'defaultOffSelfOnlyAndDeduplicated':True,'observerReplayBackgroundAndDisconnectSuppressed':True,'settingsPreserveOtherKeysAndFailedWrites':True,'realStockEditorImeSendAction':True,'composingTextSentExactlyOnce':True,'ownOutgoingAndIncomingLineCentered':True,'otherAnimationPreserved':True,'phoneUsed':False}
    (a.output/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False));win.close()
