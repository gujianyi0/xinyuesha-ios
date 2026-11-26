"""Touch the shipped counter's real GridView/ListView through its scaled viewport."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Material')
from PySide6.QtCore import QEventLoop, QTimer, QUrl, QMetaObject, Q_ARG, Q_RETURN_ARG, QPoint, QPointF, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QFontDatabase, QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem, QQuickWindow
from PySide6.QtTest import QTest

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--payload', type=Path, default=Path('android/payload'))
p.add_argument('--work-dir', type=Path, required=True)
p.add_argument('--baseline', action='store_true')
p.add_argument('--empty-only', action='store_true')
a = p.parse_args()
a.work_dir.mkdir(parents=True, exist_ok=True)
logs = []
qInstallMessageHandler(lambda k, c, m: logs.append(m))
app = QGuiApplication([])
font = Path('C:/Windows/Fonts/msyh.ttc')
if font.exists():
    font_id = QFontDatabase.addApplicationFont(str(font))
    app.setFont(QFont(QFontDatabase.applicationFontFamilies(font_id)[0]))


def pump(ms=70):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
    base = Path(tmp)
    def put(name, text):
        target = base / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding='utf-8')
    put('Fk/qmldir', 'module Fk\nsingleton Lua 1.0 Lua.qml\nsingleton SkinBank 1.0 SkinBank.qml\n')
    put('Fk/Lua.qml', 'pragma Singleton\nimport QtQuick\nQtObject{function tr(s){return s;}function ev(s){return {};}}')
    put('Fk/SkinBank.qml', 'pragma Singleton\nimport QtQuick\nQtObject{function getCardPicture(s){return "";}}')
    for name in ['CardCounter.qml', 'CounterViewport.qml', 'SuitIcon.qml']:
        shutil.copyfile(a.payload / 'card-counter' / name, base / name)
    source = (base / 'CardCounter.qml').read_text(encoding='utf-8')
    source = source.replace('objectName: "fkCardCounter"', 'objectName: "fkCardCounter"\n property alias testGrid:cards\n property alias testKnown:knownCards')
    put('CardCounter.qml', source)
    put('Main.qml', '''import QtQuick
import QtQuick.Controls
Window {
 id:win;width:1200;height:540;visible:true;property int reads:0;property int tick:0;property bool emptyKnowledge:false
 function sample(){
  const rows=[],hands=[],top=[],bottom=[];
  const details={suits:[1,1,1,0,0],points:Array(70).fill(0)};
  for(let i=0;i<300;i++)rows.push({key:"c"+i,name:"Card "+i,kind:i%3+1,total:5,unseen:3+tick%2,discard:1,hand:1,details:{unseen:details,discard:details,hand:details}});
  for(let i=0;i<40;i++){
   const row={token:"2:"+i,id:i,key:"c"+i,name:"Card "+i,suit:1,number:7,ownerId:2,owner:"Player 2",position:i+1,uncertain:false};
   hands.push(row);top.push(row);bottom.push(row);
  }
  return {ready:true,rows:rows,total:1500,unseen:900,discard:300,hand:300,knowledge:emptyKnowledge?{hands:[],top:[],bottom:[]}:{hands:hands,top:top,bottom:bottom}};
 }
 CounterViewport{id:viewport;CardCounter{id:counter;selectedKey:"c0";readSnapshot:function(){win.reads++;return win.sample();};cardPicture:function(){return "";}}}
 function open(){counter.open();}
 function close(){counter.close();}
 function resetGrid(){counter.testGrid.cancelFlick();counter.testGrid.positionViewAtBeginning();counter.selectedKey="c0";}
 function setScope(s){counter.scope=s;}
 function narrow(){win.width=852;win.height=393;}
 function update(){tick++;counter.refresh();}
 function emptyKnown(){emptyKnowledge=true;counter.refresh();counter.scope="hands";}
 function state(){const v=counter.knowledgeOpen?counter.testKnown:counter.testGrid;const p=v.mapToItem(win.contentItem,0,0);return JSON.stringify({scope:counter.scope,normalCount:counter.rows.length,knownCount:counter.testKnown.count,selected:counter.selectedKey,expanded:counter.expanded,y:v.contentY,origin:v.originY,moving:v.moving,reads:reads,x:p.x,top:p.y,w:v.width*viewport.contentScale,h:v.height*viewport.contentScale,scale:viewport.contentScale});}
}''')
    engine = QQmlApplicationEngine()
    engine.addImportPath(str(base))
    engine.load(QUrl.fromLocalFile(str(base / 'Main.qml')))
    assert engine.rootObjects(), logs
    win = engine.rootObjects()[0]
    def call(name, *args):
        return QMetaObject.invokeMethod(win, name, Qt.DirectConnection, *[Q_ARG('QVariant', v) for v in args])
    def state():
        return json.loads(QMetaObject.invokeMethod(win, 'state', Qt.DirectConnection, Q_RETURN_ARG('QVariant')))
    def descendants(item):
        yield item
        for child in item.childItems():
            yield from descendants(child)
    def item(name):
        return next(n for n in descendants(win.contentItem()) if n.objectName() == name)
    device = QTest.createTouchDevice()
    def touch(dx, dy=0, *, settled=True, hold_ms=0):
        s = state()
        x = round(s['x'] + s['w'] * (.78 if dx < 0 else .22 if dx > 0 else .5))
        y = round(s['top'] + s['h'] * (.8 if dy < 0 else .2 if dy > 0 else .5))
        q = QTest.touchEvent(win, device)
        q.press(0, QPoint(x, y), win).commit()
        pump(20)
        for step in range(1, 11):
            q = QTest.touchEvent(win, device)
            q.move(0, QPoint(x + round(dx * step / 10), y + round(dy * step / 10)), win).commit()
            pump(18)
        if hold_ms:
            pump(hold_ms)
        during = state()
        q = QTest.touchEvent(win, device)
        q.release(0, QPoint(x + dx, y + dy), win).commit()
        pump(350 if settled else 20)
        return during
    def tap(name):
        n = item(name)
        pt = n.mapToItem(win.contentItem(), QPointF(n.width()/2, n.height()/2))
        q = QTest.touchEvent(win, device)
        q.press(0, QPoint(round(pt.x()), round(pt.y())), win).commit()
        pump(20)
        q = QTest.touchEvent(win, device)
        q.release(0, QPoint(round(pt.x()), round(pt.y())), win).commit()
        pump()
    checks = []
    call('open')
    pump()
    before_first_swipe = state()
    during_first_swipe = touch(-round(state()['w']*.48), hold_ms=650)
    if a.baseline:
        assert state()['scope'] == 'unseen', state()
        result = {'baselineHorizontalSwipeIgnored': True, 'qt': __import__('PySide6').__version__, 'realDevice': False}
    elif a.empty_only:
        call('emptyKnown');pump()
        for expected in ['top','bottom']:
            touch(-round(state()['w']*.48))
            assert state()['scope']==expected,(expected,state())
        for expected in ['top','hands','hand']:
            touch(round(state()['w']*.48))
            assert state()['scope']==expected,(expected,state())
        assert state()['normalCount']==300, 'leaving an empty known page must immediately restore the normal card catalogue'
        result={'checks':['empty known-hand/top/bottom lists remain swipeable in both directions','returning from an empty known page immediately restores the normal card catalogue'],'qt':__import__('PySide6').__version__,'realDevice':False}
    else:
        assert state()['scope'] == 'discard', state()
        assert during_first_swipe['reads'] == before_first_swipe['reads'], (before_first_swipe, during_first_swipe)
        assert state()['reads'] == before_first_swipe['reads']+1, (before_first_swipe, state())
        checks.append('a held horizontal touch pauses snapshots, then refreshes the new normal tab exactly once')
        assert state()['selected'] == 'c0', 'horizontal swipe must cancel card tapping'
        checks.append('physical touch changes unseen to discard without selecting a different card')
        scopes = ['unseen', 'discard', 'hand', 'hands', 'top', 'bottom']
        for expected in scopes[2:]:
            touch(-round(state()['w']*.48))
            assert state()['scope'] == expected, (expected, state())
        touch(-round(state()['w']*.48))
        assert state()['scope'] == 'bottom', state()
        for expected in reversed(scopes[:-1]):
            touch(round(state()['w']*.48))
            assert state()['scope'] == expected, (expected, state())
            if expected in scopes[:3]:
                assert state()['normalCount']==300,(expected,state())
        touch(round(state()['w']*.48))
        assert state()['scope'] == 'unseen', state()
        checks.append('six scopes traverse both directions and stop at the first/last boundary')
        for scope in scopes:
            call('setScope', scope)
            pump()
            before = state()
            during = touch(0, -round(before['h']*.55))
            after = state()
            assert after['scope'] == scope, (scope, after)
            assert after['y'] > before['y']+25 or during['y'] > before['y']+25, (scope, before, during, after)
        checks.append('real vertical touch scrolls all six scopes without switching pages')
        call('setScope', 'unseen'); pump()
        before = state()
        # Clearly vertical intent, with ordinary horizontal finger drift.
        touch(12, -round(before['h']*.5))
        assert state()['scope'] == 'unseen', state()
        checks.append('diagonal drift during vertical scrolling does not change scope')
        tap('scope-top')
        assert state()['scope'] == 'top', state()
        tap('scope-hand')
        assert state()['scope'] == 'hand', state()
        checks.append('the original clickable tabs continue to work')
        call('setScope','unseen');call('resetGrid');pump()
        s=state();x=round(s['x']+s['w']*.3);y=round(s['top']+41*s['scale'])
        q=QTest.touchEvent(win,device);q.press(0,QPoint(x,y),win).commit();pump(20)
        q=QTest.touchEvent(win,device);q.release(0,QPoint(x,y),win).commit();pump()
        assert state()['selected']=='c1' and state()['scope']=='unseen',state()
        checks.append('a real tap still selects the tapped card without changing scope')
        call('narrow'); pump()
        call('setScope', 'unseen'); pump()
        touch(-round(state()['w']*.48))
        assert state()['scope'] == 'discard' and state()['scale'] < 1, state()
        before = state()
        touch(0, -round(before['h']*.5))
        assert state()['y'] > before['y']+25 and state()['scope'] == 'discard', state()
        checks.append('scaled narrow phone viewport supports horizontal and vertical touch')
        call('close'); call('open'); pump()
        touch(-round(state()['w']*.48))
        assert state()['scope'] == 'hand' and state()['expanded'], state()
        checks.append('closing and reopening leaves exactly one functional swipe path')
        result = {'checks': checks, 'qt': __import__('PySide6').__version__, 'realDevice': False}
    errors = [m for m in logs if any(t in m for t in ['TypeError','ReferenceError','Binding loop','Cannot assign','Unable to assign'])]
    assert not errors, errors
    result['errors'] = errors
    (a.work_dir / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    win.grabWindow().save(str(a.work_dir / 'counter-swipe.png'))
    print(json.dumps(result))
    win.close()
    engine.deleteLater()
    app.processEvents()
