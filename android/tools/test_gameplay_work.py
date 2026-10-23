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
parser.add_argument('--overview',action='store_true',help='Measure steady lobby/utility page traversal, including actual timers')
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
    if args.overview:
        for file,function in [('CounterHost.qml','refreshCompatibility(rootItem)'),('SocialHost.qml','refreshRoomBridge()')]:
            copied=base/'card-counter'/file
            source=copied.read_text(encoding='utf-8')
            source=source.replace('  id: host','  id: host\n  property int testTraversals: 0',1)
            marker='    const window = host.Window.window;' if file=='CounterHost.qml' else '    let anchor = null;'
            source=source.replace(marker,'    host.testTraversals++;\n'+marker,1)
            copied.write_text(source,encoding='utf-8')
    put('Main.qml','''import QtQuick
import QtQuick.Layouts
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
  GridView {id:overviewGrid;width:300;height:300;cellWidth:100;cellHeight:140;model:20
   delegate:Item {width:93;height:130;property var generalCardList:[];property bool draggingCard:false;property var dataModel:({})}
  }
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
 property var testStack:null
 Component {id:testStackFactory
  Item {
   property var currentItem:utilityPage;property int depth:2;property bool busy:false
   property alias lobby: lobbyPage;property alias utility: utilityPage;property alias room: roomPage
   function get(index){return currentItem;}function push(){}
   Item {id:lobbyPage;property int lobbyPlayerNum:1;property int serverPlayerNum:1;property alias roomModel:testRooms
    ListModel {id:testRooms}
   }
   Item {id:utilityPage;objectName:"largeOverview"}
   Item {id:roomPage;width:1200;height:540
    property var gameComponent:null;property alias gameContent:waitingLoader.item;property alias loader:waitingLoader
    function showTable(){waitingLoader.sourceComponent=tableFactory;}
    function showWaiting(){waitingLoader.sourceComponent=waitingFactory;}
    Component {id:tableFactory
     Item {property var dataModel:({});Rectangle {y:400;width:70;height:35;property string text:"Chat";signal clicked()}}
    }
    Loader {id:waitingLoader;width:1000;height:480;x:90;y:30;scale:0.9;active:false;sourceComponent:waitingFactory}
    Component {id:waitingFactory
     Item {property bool isOwner:true;property bool isAllReady:false
      property alias invite:inviteButton
      RowLayout {id:actions;anchors.right:parent.right;anchors.rightMargin:35;y:390;spacing:8
       Rectangle {id:inviteButton;objectName:"waitingRoomInviteButton";implicitWidth:0;implicitHeight:35;property string text:"Invite Players";signal clicked();visible:!Config.observing}
       Rectangle {implicitWidth:70;implicitHeight:35;property string text:"Chat";signal clicked()}
       Rectangle {implicitWidth:90;implicitHeight:35;property string text:"Take Seat";signal clicked();visible:Config.observing}
       Rectangle {implicitWidth:100;implicitHeight:35;property string text:"Ready";signal clicked();visible:!Config.observing}
      }
      Timer {interval:60;running:true;onTriggered:inviteButton.implicitWidth=100}
     }
    }
   }
  }
 }
 function setupOverview(){
  Ltk.roomScene=null;counter.settingsReady=true;
  testStack=testStackFactory.createObject(page);
  if ("navigationRoot" in counter) counter.navigationRoot=page;
  Mediator.commandGot(null,"EnterLobby",[]);
  Mediator.commandGot(null,"PushPage",[]);
 }
 function overviewLobby(){testStack.currentItem=testStack.lobby;Mediator.commandGot(null,"PopPage",[]);}
 function overviewPage(){testStack.currentItem=testStack.utility;Mediator.commandGot(null,"PushPage",[]);}
 function overviewGridScale(){return overviewGrid.itemAtIndex(0).scale;}
 function traversalMetrics(){return JSON.stringify({counter:counter.testTraversals,social:social.testTraversals});}
 function waitingRoom(){Config.observing=false;testStack.currentItem=testStack.room;testStack.room.loader.active=true;Mediator.commandGot(null,"EnterRoom",[0,0,{roomId:123}]);}
 function resultPage(){testStack.room.showTable();Mediator.commandGot(null,"StartGame",[]);Mediator.commandGot(null,"GameOver",[]);}
 function earlyBack(){Mediator.commandGot(null,"BackToRoom",[]);}
 function resetWaiting(){testStack.room.loader.active=false;Mediator.commandGot(null,"RestartGame",[]);testStack.room.showWaiting();testStack.room.loader.active=true;return social.roomLauncherReady;}
 function moveWaiting(){testStack.room.loader.x=35;testStack.room.loader.y=9;testStack.room.loader.scale=0.72;}
 function observerRoom(){Config.observing=true;}
 function seatedRoom(){Config.observing=false;testStack.room.gameContent.y=25;testStack.room.gameContent.scale=0.85;}
 function positionState(){
  const a=social.inviteAnchor;const pos=a?a.mapToItem(social,0,0):({x:0,y:0});const end=a?a.mapToItem(social,0,a.height):({x:0,y:0});const h=Math.abs(end.y-pos.y);
  const launcher=social.roomInlineLauncher || Array.from(social.children).find(c=>c.objectName==="friendsLauncher");
  const p=launcher.mapToItem(social,0,0);const q=launcher.mapToItem(social,launcher.width,launcher.height);
  let overlaps=0,duplicates=0;
  for(const n of launcher.parent.children){
   if(n.objectName==="roomFriendsLauncher")duplicates++;
   if(n===launcher || !n.visible || !(n.width>0 && n.height>0))continue;
   const b=n.mapToItem(social,0,0);const e=n.mapToItem(social,n.width,n.height);
   if(Math.min(q.x,e.x)-Math.max(p.x,b.x)>0.1 && Math.min(q.y,e.y)-Math.max(p.y,b.y)>0.1)overlaps++;
  }
  return JSON.stringify({ready:social.roomLauncherReady,inline:!!social.roomInlineLauncher,duplicates:duplicates,overlaps:overlaps,match:social.matchViewActive,visible:social.visible,launcherVisible:launcher.visible,x:p.x,y:p.y,expectedX:Math.max(8,pos.x-h*1.72-6),expectedY:pos.y});
 }
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
    if args.overview:
        invoke('setupOverview');pump(.3)
        def measure_overview():
            initial=json.loads(invoke('traversalMetrics'));gaps=[];tick=[time.perf_counter()]
            pulse=QTimer();pulse.setInterval(16)
            def sample():
                now=time.perf_counter();gaps.append((now-tick[0])*1000);tick[0]=now
            pulse.timeout.connect(sample);pulse.start();pump(2.25);pulse.stop()
            final=json.loads(invoke('traversalMetrics'))
            return {'traversals':{k:final[k]-initial[k] for k in initial},'max_event_loop_gap_ms':round(max(gaps,default=0),1)}
        overview={'utility':measure_overview()}
        invoke('overviewLobby');pump(.3);overview['lobby']=measure_overview()
        invoke('overviewPage');pump(.3);overview['utility_return']=measure_overview()
        result['overview']=overview
        result['overview_grid_delegate_scale']=invoke('overviewGridScale')
        if not args.measure_only:
            assert all(not sum(v['traversals'].values()) for v in overview.values()),overview
            assert result['overview_grid_delegate_scale']==1,'overview grid delegates must not be traversed/adapted'
        invoke('waitingRoom');pump(.2);initial_room=json.loads(invoke('positionState'))
        invoke('observerRoom');pump(.05);observer_room=json.loads(invoke('positionState'))
        invoke('seatedRoom');pump(.05);seated_room=json.loads(invoke('positionState'))
        invoke('resultPage');pump(.02);result_page=json.loads(invoke('positionState'))
        invoke('earlyBack');pump(.02);old_table=json.loads(invoke('positionState'))
        early_ready=invoke('resetWaiting');pump(.2);reset_room=json.loads(invoke('positionState'))
        invoke('moveWaiting');pump(.1);moved_room=json.loads(invoke('positionState'))
        result['waiting_room_positions']={'initial':initial_room,'observer':observer_room,'seated':seated_room,'results':result_page,'old_table_after_back':old_table,'ready_before_layout':early_ready,'reset':reset_room,'moved':moved_room}
        if not args.measure_only:
            assert result_page['match'] and not result_page['visible'],'GameOver does not expose the friends launcher over results'
            assert not early_ready,'new waiting-room buttons must finish layout before the launcher is shown'
            assert not old_table['ready'] and not old_table['launcherVisible'],'do not anchor to the old game table Chat button before WaitingRoom exists'
            for state in [initial_room,observer_room,seated_room,reset_room,moved_room]:
                assert state['visible'] and state['launcherVisible'],state
                assert state['duplicates']<=1 and state['overlaps']==0,state
                assert abs(state['y']-state['expectedY'])<.01,state
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
