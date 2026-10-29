# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the stock room drawer with real touch, nested lists and controls."""
import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Material')
from PySide6.QtCore import QObject, Property, Slot, QUrl, QPoint, Qt, QMetaObject, Q_ARG, Q_RETURN_ARG, QEventLoop, QTimer, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest

p = argparse.ArgumentParser()
p.add_argument('--payload', type=Path, default=Path('runtime'))
p.add_argument('--core', type=Path)
p.add_argument('--work-dir', type=Path, required=True)
a = p.parse_args()
a.work_dir.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parents[1]
stock = a.core or repo / 'runtime'
source = (stock / 'Fk/Pages/Common/RoomPage.qml').read_text(encoding='utf8')
start = source.rindex('  W.PopupLoader {', 0, source.index('    id: roomDrawer'))
end = source.index('\n  Danmu {', start)
drawer = source[start:end]
assert drawer.count('SwipeView {') == 1 and 'interactive: false' in drawer
drawer = drawer.replace('SwipeView {', 'SwipeView { objectName: "drawerPages"', 1)
logs = []
qInstallMessageHandler(lambda kind, context, message: logs.append(message))
app = QGuiApplication([])

class SelfFixture(QObject):
    id = Property(int, lambda self: 1, constant=True)
    screenName = Property(str, lambda self: 'Self', constant=True)

class ClientFixture(QObject):
    def __init__(self):
        super().__init__()
        self.sent = []
    @Slot(str, 'QVariant')
    def notifyServer(self, command, data):
        self.sent.append((command, data.toVariant() if hasattr(data, 'toVariant') else data))

def pump(ms=100):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()

with tempfile.TemporaryDirectory(dir=a.work_dir) as temporary:
    base = Path(temporary)
    def put(name, text):
        path = base / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf8')
    put('Fk/qmldir', 'module Fk\n' + ''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Config', 'Cpp', 'Lua', 'Backend', 'Mediator', 'SkinBank']))
    put('Fk/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
 property real winWidth:1000;property real winHeight:600;property real winScale:1
 property bool replaying:false;property bool observing:true;property bool hideScreenName:false;property bool hideAllTitles:false
 property var blockedUsers:[];property string libianName:"sans-serif"
 property string roomBg:"";property string lobbyBg:"";property var enabledResourcePacks:[]
 function titleForPlayer(id){return {title:"",style:""};}
}''')
    put('Fk/Cpp.qml', 'pragma Singleton\nimport QtQuick\nQtObject {property string os:"iOS";property string path:"/fixture";}')
    put('Fk/Mediator.qml', 'pragma Singleton\nimport QtQuick\nQtObject {signal commandGot(var sender,string command,var data)}')
    put('Fk/SkinBank.qml', 'pragma Singleton\nimport QtQuick\nQtObject {function getAudioRealPath(){return undefined;}}')
    put('Fk/Backend.qml', '''pragma Singleton
import QtQuick
QtObject {function readFileFromAssets(){return "{}";}function writeFileToAssets(){return true;}function exists(){return false;}function ls(){return [];}}''')
    put('Fk/Lua.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var selfPlayer:({id:1,general:"",deputyGeneral:""})
 property int observed:0
 property var client:({changeSelf:function(pid){Lua.observed=pid;}})
 function tr(s){return s;}
 function ev(s){return s.indexOf("Fk:getAllGenerals")>=0?[]:true;}
 function getPlayersAndObservers(){const ps=[];for(let n=0;n<90;n++)ps.push({id:n+2,name:"Player "+n,general:"",deputy:"",observing:false,state:1,avatar:"",seat:n+1});return ps;}
}''')
    put('LunarLtk/qmldir', 'module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
    put('LunarLtk/Ltk.qml', '''pragma Singleton
import QtQuick
QtObject {property var roomScene:null;function getPlayer(){return null;}function getGeneralDetail(){return {skill:[]};}function getGeneralData(){return {extension:"fixture"};}function createGeneralCardModel(){return {};}}''')
    put('LunarLtk/Components/qmldir', 'module LunarLtk.Components\nCompactGeneralCardItem 1.0 CompactGeneralCardItem.qml\n')
    put('LunarLtk/Components/CompactGeneralCardItem.qml', 'import QtQuick\nItem {property var dataModel;signal clicked()}')
    widgets = ['TapHandler', 'ViewSwitcher', 'PopupLoader']
    put('Fk/Widgets/qmldir', 'module Fk.Widgets\n' + ''.join(n+' 1.0 '+n+'.qml\n' for n in widgets) + 'ButtonContent 1.0 ButtonContent.qml\n')
    for name in widgets:
        shutil.copy2(stock / ('Fk/Widgets/'+name+'.qml'), base / ('Fk/Widgets/'+name+'.qml'))
    put('Fk/Widgets/ButtonContent.qml', 'import QtQuick\nimport QtQuick.Controls\nButton {property color backgroundColor:"white";}')
    for name in ['AvatarChatBox', 'LogEdit', 'RoomGameLogEdit']:
        original = stock / ('Fk/Components/Common/'+name+'.qml')
        if original.exists():
            shutil.copy2(original, base / (name+'.qml'))
    put('Avatar.qml', 'import QtQuick\nItem {property string general;}')
    put('MetroButton.qml', 'import QtQuick.Controls\nButton {}')
    put('Fk/Components/WaitingRoom/qmldir', 'module Fk.Components.WaitingRoom\nTitleItem 1.0 TitleItem.qml\n')
    put('Fk/Components/WaitingRoom/TitleItem.qml', 'import QtQuick\nItem {property string title;property string style;}')
    shutil.copytree(a.payload / 'card-counter', base / 'card-counter')
    put('Main.qml', '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Fk
import Fk.Widgets as W
import "card-counter" as Counter
Window {
 id:win;width:1000;height:600;visible:true
 Counter.CounterHost {id:host}
 DRAWER
 function pages(){return Array.from(drawerBar.parent.children).find(c=>c.objectName==="drawerPages");}
 function listIn(page){const pending=[page];while(pending.length){const node=pending.pop();if(node.visible && "movementStarted" in node && node.orientation===ListView.Vertical)return node;if(node.children)pending.push(...Array.from(node.children));}return null;}
 function currentList(){return listIn(pages().currentItem);}
 function seed(){for(let n=0;n<90;n++){log.append({logText:"<b>Log "+n+"</b> "+"content ".repeat(n%3?5:30)});chat.append(null,{general:"",sender:2,msg:"Message "+n+" "+"content ".repeat(n%3?3:16),userName:"Player",time:"12:00"});}}
 function openDrawer(){roomDrawer.open();}
 function closeDrawer(){roomDrawer.close();}
 function install(){host.settingsReady=true;host.refreshCompatibility(Overlay.overlay);}
 function getPages(){return pages();}
 function read(){const v=currentList(),r=pages().mapToItem(win.contentItem,0,0);return JSON.stringify({page:pages().currentIndex,tab:drawerBar.currentIndex,interactive:pages().interactive,y:v?v.contentY:0,x:r.x,top:r.y,width:pages().width*Config.winScale,height:pages().height*Config.winScale,blocked:Config.blockedUsers.length,observed:Lua.observed});}
 function middle(){const v=currentList();v.cancelFlick();v.currentIndex=-1;v.positionViewAtIndex(Math.floor(v.count/2),ListView.Beginning);}
 function tab0(){drawerBar.currentIndex=0;}
 function tab1(){drawerBar.currentIndex=1;}
 function tab2(){drawerBar.currentIndex=2;}
 function tabPoint(index){const p=drawerBar.mapToItem(win.contentItem,index*100+50,20);return JSON.stringify({x:p.x,y:p.y});}
 function small(){roomDrawer.close();Config.winWidth=800;Config.winScale=.65;roomDrawer.open();}
 function liveAppend(){log.append({logText:"New live log"});chat.append(null,{general:"",sender:2,msg:"New message",userName:"Player",time:"12:01"});}
 function textPoint(){const pending=[chat];while(pending.length){const n=pending.pop();if("maximumLength" in n){const r=n.mapToItem(win.contentItem,n.width/2,n.height/2);return JSON.stringify({x:r.x,y:r.y});}if(n.children)pending.push(...Array.from(n.children));}return "{}";}
 function modeTwo(){drawerBar.model=[Lua.tr("Chat"),Lua.tr("PlayerList")];}
 function modeThree(){drawerBar.model=[Lua.tr("Log"),Lua.tr("Chat"),Lua.tr("PlayerList")];}
}'''.replace('DRAWER', drawer))
    engine = QQmlApplicationEngine()
    self_fixture = SelfFixture()
    client = ClientFixture()
    engine.rootContext().setContextProperty('Self', self_fixture)
    engine.rootContext().setContextProperty('ClientInstance', client)
    engine.rootContext().setContextProperty('AppPath', '/fixture')
    engine.addImportPath(str(base))
    engine.load(QUrl.fromLocalFile(str(base / 'Main.qml')))
    assert engine.rootObjects(), logs
    win = engine.rootObjects()[0]
    def invoke(name):
        return QMetaObject.invokeMethod(win, name, Q_RETURN_ARG('QVariant'))
    def read():
        return json.loads(invoke('read'))
    touch = QTest.createTouchDevice()
    def tap_tab(index):
        point = json.loads(QMetaObject.invokeMethod(win, 'tabPoint', Q_RETURN_ARG('QVariant'), Q_ARG('QVariant', index)))
        position = QPoint(round(point['x']), round(point['y']))
        QTest.touchEvent(win, touch).press(0, position, win).commit(); pump(20)
        QTest.touchEvent(win, touch).release(0, position, win).commit(); pump(350)
    def gesture(horizontal=True, right=False, hold=20):
        state = read()
        x, y = state['x'], state['top']
        w, h = state['width'], state['height']
        start = QPoint(round(x+w*(.25 if right else .75)) if horizontal else round(x+w*.45), round(y+h*.45))
        finish = QPoint(round(x+w*(.75 if right else .25)) if horizontal else start.x()+2, start.y() if horizontal else round(y+h*.75))
        QTest.touchEvent(win, touch).press(0, start, win).commit(); pump(hold)
        for n in range(1, 9):
            point = start + (finish-start)*n/8
            QTest.touchEvent(win, touch).move(0, point, win).commit(); pump(30)
        QTest.touchEvent(win, touch).release(0, finish, win).commit(); pump(450)
        return read()
    invoke('seed'); invoke('openDrawer'); pump(180)
    baseline = gesture()
    assert baseline['page'] == 0 and not baseline['interactive'], baseline
    # The old stock bubble sizes itself with contentWidth, which can warn
    # before this feature is installed. Preserve that exact baseline warning;
    # newly introduced binding loops or other QML errors still fail the test.
    baseline_warnings = {m for m in logs if 'AvatarChatBox.qml:148:11:' in m and 'Binding loop' in m and '"width"' in m}
    invoke('install'); pump(180)
    assert read()['interactive'], (read(), logs)
    observations = []
    for name in ['normal', 'scaled']:
        if name == 'scaled':
            invoke('small'); pump(180)
        invoke('tab0'); pump(350)
        for expected in [1, 2]:
            state = gesture(); observations.append({'layout':name,'gesture':'left','state':state})
            assert state['page'] == state['tab'] == expected, state
        state = gesture()
        assert state['page'] == state['tab'] == 2, 'last page does not wrap'
        for expected in [1, 0]:
            state = gesture(right=True); observations.append({'layout':name,'gesture':'right','state':state})
            assert state['page'] == state['tab'] == expected, state
        state = gesture(right=True)
        assert state['page'] == state['tab'] == 0, 'first page does not wrap'
        for index in [0, 1, 2]:
            tap_tab(index)
            assert read()['page'] == index
            invoke('middle'); pump(150)
            before = read()
            after = gesture(horizontal=False, hold=850)
            assert after['page'] == after['tab'] == index and before['y']-after['y'] > 35, (before, after)
            invoke('liveAppend'); pump(80)
            assert abs(read()['y'] - after['y']) < 12, 'new messages preserve a scrolled reading position'
        assert read()['blocked'] == 0 and read()['observed'] == 0, 'swipes do not invoke player actions'
        invoke('closeDrawer'); pump(80); invoke('openDrawer'); pump(180)
        assert read()['page'] == read()['tab'] == 2, 'reopening remembers the swiped tab'
        invoke('install'); pump(100)
        assert len(invoke('getPages').findChildren(QObject, 'roomDrawerSwipeSync')) == 1, 'one event connection per drawer'
    # The old stock page and this compatibility hook must leave the newer
    # core's two-tab/offset mode to its own navigation.
    invoke('modeTwo'); pump(80); assert not read()['interactive']
    invoke('modeThree'); pump(80); assert read()['interactive']
    invoke('tab1'); pump(350)
    point = json.loads(invoke('textPoint'))
    QTest.mouseClick(win, Qt.LeftButton, Qt.NoModifier, QPoint(round(point['x']), round(point['y'])))
    for key in [Qt.Key_H, Qt.Key_E, Qt.Key_L, Qt.Key_L, Qt.Key_O]:
        QTest.keyClick(win, key)
    QTest.keyClick(win, Qt.Key_Return); pump(80)
    assert client.sent == [('Chat', {'type':2, 'msg':'hello'})], client.sent
    errors = [m for m in logs if m not in baseline_warnings and any(word in m for word in ['TypeError', 'ReferenceError', 'SyntaxError', 'Binding loop', 'Cannot assign', 'Unable to assign'])]
    assert not errors, errors
    result = {'baseline':baseline,'gestures':observations,'chat_sent':True,'duplicate_connections':False,'baseline_stock_warnings':list(baseline_warnings),'errors':errors,'core':str(stock)}
    (a.work_dir / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    win.close(); engine.deleteLater(); pump(30)
