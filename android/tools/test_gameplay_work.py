"""Measure actual QML helper work under gameplay notifications, without a server."""
import argparse, json, os, shutil, tempfile, time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Material')
from PySide6.QtCore import QObject, QTimer, QUrl, QMetaObject, Q_RETURN_ARG, qInstallMessageHandler, QEventLoop, QEvent
from PySide6.QtGui import QGuiApplication, QFontDatabase, QFont
from PySide6.QtQml import QQmlApplicationEngine

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir',type=Path,required=True)
parser.add_argument('--payload',type=Path,default=Path(__file__).resolve().parents[1]/'payload')
parser.add_argument('--measure-only',action='store_true')
parser.add_argument('--platform',choices=['Android','iOS','Windows'],default='Android')
parser.add_argument('--cycles',type=int,default=0,help='Repeat match/observer/return lifecycles and check retained objects')
parser.add_argument('--result',type=Path)
args=parser.parse_args();args.work_dir.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg))
app=QGuiApplication([])
font=Path('C:/Windows/Fonts/msyh.ttc')
if font.exists():
    index=QFontDatabase.addApplicationFont(str(font));app.setFont(QFont(QFontDatabase.applicationFontFamilies(index)[0]))
with tempfile.TemporaryDirectory(dir=args.work_dir) as temp:
    base=Path(temp)
    def put(name,text):
        path=base/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text,encoding='utf-8')
    put('Fk/qmldir','module Fk\n'+''.join(f'singleton {n} 1.0 {n}.qml\n' for n in ['Config','Cpp','Lua','Backend','SkinBank','Mediator']))
    put('Fk/Config.qml','''pragma Singleton
import QtQuick
QtObject {property string roomBg:"";property string lobbyBg:"";property string serverAddr:"test";property int serverPort:9527;property string screenName:"fixture";property string password:"";property bool observing:false;property bool replaying:false;property bool consoleStartRequested:false;function saveConf(){}}''')
    put('Fk/Cpp.qml','''pragma Singleton
import QtQuick
QtObject {property string os:"PLATFORM";property var self:({id:1,screenName:"fixture",avatar:""});function notifyServer(c,d){}}'''.replace('PLATFORM',args.platform))
    put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject {function ev(s){return true;}function tr(s){return s;}function getPlayersAndObservers(){return [];}}''')
    put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject {property int writes:0;property var files:({});function readFileFromAssets(p){return files[p]||"";}function writeFileToAssets(p,v){writes++;files=Object.assign({},files,{[p]:v});return true;}function copyToClipboard(s){}}''')
    put('Fk/SkinBank.qml','''pragma Singleton
import QtQuick
QtObject {function getCardPicture(n){return "";}function getGeneralExtraPic(n,p){return "";}function getGeneralPicture(n){return "";}}''')
    put('Fk/Mediator.qml','''pragma Singleton
import QtQuick
QtObject {signal commandGot(var sender,string command,var data)}''')
    put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
    put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject {property var roomScene:null;}')
    shutil.copytree(args.payload/'card-counter',base/'card-counter')
    put('Main.qml','''import QtQuick
import Fk
import LunarLtk
import "card-counter" as Counter
Window {
 id:win;width:1200;height:540;visible:true
 property int contextChanges:0
 property int popupScans:0
 Counter.CounterHost {id:counter}
 Item {id:page;anchors.fill:parent
  Counter.SocialHost {id:social}
  Repeater {model:3500;Item {width:1;height:1}}
 }
 Item {id:scene;width:1200;height:540;property var dataModel:({});property var popupItem:null
  property alias drawPile:deck
  Item {id:deck;property string source:"card-back";width:32;height:42}
  Item {id:choice;property var generalCardList:[];property bool draggingCard:false;property var dataModel:({});width:800;height:600}
 }
 property var stressScene:null
 Component {id:stressSceneFactory
  Item {width:1200;height:540;property var dataModel:({});property var popupItem:null
   property alias drawPile:stressDeck;property alias choice:stressChoice
   Item {id:stressDeck;property string source:"card-back";width:32;height:42}
   Item {id:stressChoice;property var generalCardList:[];property bool draggingCard:false;property var dataModel:({});width:800;height:600}
  }
 }
 Connections {target:social.socialClient;function onContextChanged(){win.contextChanges++;}}
 function prepare(){
  social.profiles={"test:9527/1":{enabled:false}};social.profilesLoaded=true;
  Mediator.commandGot(null,"EnterLobby",[]);
  Mediator.commandGot(null,"StartGame",[]);
 }
 function burst(){let before=contextChanges;let t=Date.now();
  for(let i=0;i<1000;i++) Mediator.commandGot(null,["MoveCards","UpdateCard","UpdateSkill","PropertyUpdate"][i%4],[]);
  return JSON.stringify({milliseconds:Date.now()-t,contextChanges:contextChanges-before});
 }
 function sameContext(){let before=contextChanges;let t=Date.now();
  for(let i=0;i<1000;i++) social.updateContext();
  return JSON.stringify({milliseconds:Date.now()-t,contextChanges:contextChanges-before});
 }
 function scan(){let t=Date.now();for(let i=0;i<5;i++)counter.refreshCompatibility();return Date.now()-t;}
 function enterScene(){Ltk.roomScene=scene;counter.settingsReady=true;}
 function measureMatchScan(){let t=Date.now();for(let i=0;i<5;i++)counter.refreshCompatibility();return Date.now()-t;}
 function openChoice(){scene.popupItem=choice;}
 function choiceScale(){return choice.scale;}
 function state(){return JSON.stringify({match:social.matchViewActive,visible:social.visible,state:social.gameState,popup:!!counter.popup,deck:!!counter.deckHit});}
 function observe(){Config.observing=true;Mediator.commandGot(null,"StartGame",[]);}
 function leave(){Ltk.roomScene=null;Mediator.commandGot(null,"EnterLobby",[]);}
 function utility(){Mediator.commandGot(null,"PushPage",[]);return social.visible;}
 function back(){Mediator.commandGot(null,"PopPage",[]);return social.visible;}
 function enterFreshScene(){Config.observing=false;stressScene=stressSceneFactory.createObject(win.contentItem);Ltk.roomScene=stressScene;Mediator.commandGot(null,"StartGame",[]);}
 function freshChoice(){stressScene.popupItem=stressScene.choice;}
 function leaveFreshScene(){Ltk.roomScene=null;stressScene.destroy();stressScene=null;Mediator.commandGot(null,"EnterLobby",[]);}
}''')
    engine=QQmlApplicationEngine();engine.addImportPath(str(base))
    client=QObject();engine.rootContext().setContextProperty('ClientInstance',client)
    engine.load(QUrl.fromLocalFile(str(base/'Main.qml')))
    assert engine.rootObjects(),logs
    window=engine.rootObjects()[0]
    def invoke(name):return QMetaObject.invokeMethod(window,name,Q_RETURN_ARG('QVariant'))
    def pump(seconds):
        # Use an actual event loop: repeated processEvents() alone does not
        # drain DeferredDelete and would falsely report destroyed scene leaks.
        loop=QEventLoop();QTimer.singleShot(max(1,round(seconds*1000)),loop.quit);loop.exec()
        app.sendPostedEvents(None,QEvent.DeferredDelete)
    pump(.1);invoke('prepare');pump(.05)
    result={'platform':args.platform,'gameplay_burst':json.loads(invoke('burst')),'same_context':json.loads(invoke('sameContext')),'five_idle_scans_ms':invoke('scan')}
    invoke('enterScene');pump(.65)
    result['match_state']=json.loads(invoke('state'));result['five_match_scans_ms']=invoke('measureMatchScan')
    beats=[];last=[time.perf_counter()]
    heartbeat=QTimer();heartbeat.setInterval(16)
    def beat():
        now=time.perf_counter();beats.append((now-last[0])*1000);last[0]=now
    heartbeat.timeout.connect(beat);heartbeat.start();pump(2.2);heartbeat.stop()
    result['match_event_loop_max_gap_ms']=round(max(beats,default=0),1)
    invoke('openChoice');pump(.05);result['popup_scale']=invoke('choiceScale')
    invoke('observe');pump(.05);result['observe_state']=json.loads(invoke('state'))
    invoke('leave');pump(.05);result['lobby_state']=json.loads(invoke('state'))
    result['utility_visible']=invoke('utility');result['back_visible']=invoke('back')
    if args.cycles:
        engine.collectGarbage();pump(.03)
        from collections import Counter
        initial_types=Counter(o.metaObject().className().split('_QML')[0] for o in window.findChildren(QObject))
        initial_objects=len(window.findChildren(QObject));counts=[];writes_before=engine.singletonInstance('Fk','Backend').property('writes')
        changes=[]
        for cycle in range(args.cycles):
            invoke('enterFreshScene');pump(.02)
            current=json.loads(invoke('state'))
            assert current['popup'] and current['deck'],(cycle,current)
            changes.append(json.loads(invoke('burst'))['contextChanges'])
            invoke('freshChoice');pump(.01)
            invoke('observe');pump(.01)
            assert not json.loads(invoke('state'))['visible']
            invoke('leaveFreshScene');pump(.02)
            after=json.loads(invoke('state'))
            assert not after['popup'] and not after['deck'],(cycle,after)
            counts.append(len(window.findChildren(QObject)))
        engine.collectGarbage();pump(.03)
        result['lifecycle_stress']={'cycles':args.cycles,'gameplay_packets':args.cycles*1000,
          'social_context_changes':sum(changes),'initial_objects':initial_objects,
          'final_objects':len(window.findChildren(QObject)),'max_objects_after_return':max(counts),
          'profile_writes':engine.singletonInstance('Fk','Backend').property('writes')-writes_before,
          'retained_type_growth':dict(Counter(o.metaObject().className().split('_QML')[0] for o in window.findChildren(QObject))-initial_types)}
        if args.result:args.result.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        assert result['lifecycle_stress']['final_objects']<=initial_objects+5,result['lifecycle_stress']
        assert not sum(changes),result['lifecycle_stress']
    errors=[m for m in logs if 'ReferenceError' in m or 'TypeError' in m or 'is not a type' in m or 'Cannot assign' in m]
    result['qml_errors']=errors
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if args.result:args.result.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    if not args.measure_only:
        assert not errors,errors
        assert result['gameplay_burst']['contextChanges']==0,'gameplay commands must not rebind social context'
        assert result['same_context']['contextChanges']==0,'unchanged social context must not invalidate UI bindings'
        assert result['match_state']['popup'] and result['match_state']['deck'],'counter attaches on scene changes'
        assert result['match_state']['match'] and not result['match_state']['visible'],'friends hidden during match'
        assert result['observe_state']['state']=='observing' and not result['observe_state']['visible'],'observer lifecycle retained'
        assert result['lobby_state']['state']=='lobby' and result['lobby_state']['visible'],'lobby launcher recovers'
        assert not result['utility_visible'] and result['back_visible'],'native utility pages still hide the friend launcher'
        assert result['popup_scale']<1,'new room popups are adapted from popupItemChanged'
        assert result['five_match_scans_ms']<=5,'full UI scan must be skipped in active Android matches'
        print('PASS: gameplay fast path, stable context, match scan guard and scene/social lifecycle')
    engine.deleteLater();app.processEvents()
