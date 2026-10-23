"""Exercise the actual counter while a large catalogue updates and flicks."""
import argparse, ctypes, ctypes.util, json, os, shutil, tempfile, time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QObject, QEvent, QEventLoop, QTimer, QUrl, QMetaObject, Q_RETURN_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QInputMethodEvent, QTextCharFormat, QColor, QFontDatabase, QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir',type=Path,required=True)
parser.add_argument('--payload',type=Path,default=Path(__file__).resolve().parents[1]/'runtime')
parser.add_argument('--measure-only',action='store_true')
parser.add_argument('--result',type=Path)
parser.add_argument('--lua-library')
args=parser.parse_args();args.work_dir.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg))
app=QGuiApplication([])
font=Path('C:/Windows/Fonts/msyh.ttc')
if font.exists():
    index=QFontDatabase.addApplicationFont(str(font))
    app.setFont(QFont(QFontDatabase.applicationFontFamilies(index)[0]))

def pump(seconds):
    loop=QEventLoop();QTimer.singleShot(round(seconds*1000),loop.quit);loop.exec()
    app.sendPostedEvents(None,QEvent.DeferredDelete)

with tempfile.TemporaryDirectory(dir=args.work_dir) as temp:
    base=Path(temp)
    def put(name,text):
        p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf8')
    put('Fk/qmldir','module Fk\nsingleton Lua 1.0 Lua.qml\nsingleton SkinBank 1.0 SkinBank.qml\n')
    put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject {function tr(s){return s;}function ev(s){return {};}}')
    put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject {function getCardPicture(s){return "";}}')
    source=(args.payload/'card-counter/CardCounter.qml').read_text(encoding='utf8')
    assert source.count('objectName: "fkCardCounter"')==1 and source.count('id:tile\n')==1
    source=source.replace('objectName: "fkCardCounter"','objectName: "fkCardCounter"\n  property int testCreates:0\n  property alias testGrid:cards\n  property alias testSearch:search')
    source=source.replace('id:tile\n','id:tile\n            Component.onCompleted:root.testCreates++\n')
    put('CardCounter.qml',source)
    shutil.copyfile(args.payload/'card-counter/SuitIcon.qml',base/'SuitIcon.qml')
    put('Main.qml','''import QtQuick
import QtQuick.Controls
Window {
 id:win;width:1200;height:540;visible:true
 property int tick:0;property int reads:0
 property bool failSnapshot:false
 property bool extraCards:false
 function sample(){
  const rows=[];
  for(let i=0;i<300;i++){
   let points=Array(70).fill(0);points[1]=1;
   let details={unseen:{suits:[1,0,0,0,0],points:points},discard:{suits:[0,0,0,0,0],points:Array(70).fill(0)},hand:{suits:[0,0,0,0,0],points:Array(70).fill(0)}};
   rows.push({key:"c"+i,name:"卡牌"+i,kind:i%3+1,total:i===17?3+tick%2:3,unseen:i===17?tick%2:3,hand:0,discard:0,details:details});
  }
  if(extraCards) for(let n=0;n<5;n++) rows.unshift({key:"generated"+n,name:"衍生牌"+n,kind:2,total:1,unseen:1,hand:0,discard:0,details:{}});
  return {ready:true,rows:rows,total:900,unseen:900-tick%2,hand:0,discard:0};
 }
 CardCounter {id:counter;selectedKey:"c17";readSnapshot:function(){win.reads++;if(win.failSnapshot) throw new Error("fixture snapshot unavailable");return win.sample();};cardPicture:function(n){return "";}}
 function open(){counter.open();}
 function close(){counter.close();}
 function change(){tick++;counter.refresh();}
 function scrollMiddle(){counter.testGrid.positionViewAtIndex(120,GridView.Beginning);counter.testGrid.contentY+=17;}
 function addGenerated(){extraCards=true;counter.refresh();}
 function removeGenerated(){extraCards=false;counter.refresh();}
 function hideZero(){counter.hideZero=true;}
 function showZero(){counter.hideZero=false;}
 function choose(){counter.selectedKey="c18";}
 function search(){counter.filterText="c29";}
 function clearSearch(){counter.filterText="";}
 function startFlick(){counter.testGrid.contentY=0;counter.testGrid.flick(0,-2000);}
 function stopFlick(){counter.testGrid.cancelFlick();}
 function focusSearch(){counter.testSearch.forceActiveFocus();counter.testSearch.text="测试输入";}
 function failRead(){counter.testSearch.text="";win.failSnapshot=true;counter.refresh();}
 function recoverRead(){win.failSnapshot=false;counter.refresh();}
 function openKnown(){counter.knowledgeOpen=true;counter.snapshot={knowledge:{hands:[{token:"2:27",id:27,key:"slash",name:"杀",suit:1,number:7,owner:"玩家",position:0,uncertain:false}],top:[{token:"28",id:28,key:"jink",name:"闪",suit:3,number:2,owner:"",position:1,uncertain:false}],bottom:[]}};}
 function knownTop(){counter.knowledgeScope="top";}
 function knownEmpty(){counter.snapshot={knowledge:{hands:[],top:[],bottom:[]}};}
 function inputStyle(){const f=counter.testSearch;return JSON.stringify({preedit:f.preeditText,text:f.text,color:f.color.toString(),background:f.background.color.toString(),selected:f.selectedTextColor.toString()});}
 function inputGeometry(){const field=counter.testSearch;const cursor=field.cursorRectangle;return JSON.stringify({y:cursor.y,height:cursor.height,fieldHeight:field.height,topPadding:field.topPadding,bottomPadding:field.bottomPadding});}
 function state(){return JSON.stringify({reads:reads,creates:counter.testCreates,count:counter.rows.length,gridCount:counter.testGrid.count,moving:counter.testGrid.moving,y:counter.testGrid.contentY,topKey:counter.rows[Math.max(0,Math.floor((counter.testGrid.contentY-counter.testGrid.originY)/counter.testGrid.cellHeight))*5]?.key || "",selected:counter.selectedRow?counter.selectedRow.key:"",amount:counter.selectedRow?counter.selectedRow.unseen:-1});}
}''')
    engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.load(QUrl.fromLocalFile(str(base/'Main.qml')))
    assert engine.rootObjects(),logs
    window=engine.rootObjects()[0]
    def invoke(name):return QMetaObject.invokeMethod(window,name,Q_RETURN_ARG('QVariant'))
    def state():return json.loads(invoke('state'))
    invoke('open');pump(.08);invoke('scrollMiddle');pump(.08);initial=state();assert initial['count']==300,initial
    for _ in range(20):invoke('change');pump(.01)
    updated=state()
    assert initial['y']>500,initial
    if not args.measure_only:
        assert abs(updated['y']-initial['y'])<1,(initial,updated)
        invoke('addGenerated');pump(.06);generated=state()
        assert generated['count']==305 and generated['topKey']==updated['topKey'],(updated,generated)
        invoke('removeGenerated');pump(.06);removed=state()
        assert removed['count']==300 and removed['topKey']==updated['topKey'],(updated,removed)
    else:generated=None;removed=None
    invoke('startFlick');pump(.05);start=state();pump(.7);moving=state()
    invoke('stopFlick');pump(.1);stopped=state()
    invoke('hideZero');pump(.02);assert state()['count']==299,state()
    invoke('change');pump(.02);assert state()['count']==300,state()
    invoke('showZero');invoke('choose');pump(.02);assert state()['selected']=='c18',state()
    invoke('search');pump(.02);assert state()['count']==11,state()
    invoke('clearSearch');pump(.02);assert state()['count']==300,state()
    invoke('focusSearch');pump(.02);raw_geometry=invoke('inputGeometry');assert raw_geometry,logs
    input_geometry=json.loads(raw_geometry)
    # Reproduce Qt 6.8 iOS's exact marked-text format, including its fixed
    # light-blue background and absent foreground. No native keyboard needed.
    field=app.focusObject();assert field is not None
    fmt=QTextCharFormat();fmt.setBackground(QColor(206,221,238))
    event=QInputMethodEvent('wuxie',[QInputMethodEvent.Attribute(QInputMethodEvent.TextFormat,0,5,fmt)])
    app.sendEvent(field,event);pump(.03)
    composing=json.loads(invoke('inputStyle'))
    assert composing['preedit']=='wuxie' and composing['color']=='#182b30' and composing['background']=='#ceddee',composing
    def luminance(value):
        rgb=[int(value[i:i+2],16)/255 for i in (1,3,5)]
        linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
        return sum(a*b for a,b in zip(linear,(.2126,.7152,.0722)))
    assert (luminance('#ceddee')+.05)/(luminance(composing['color'])+.05)>7,composing
    window.grabWindow().save(str(args.work_dir/'ios-preedit.png'))
    commit=QInputMethodEvent();commit.setCommitString('无懈');app.sendEvent(field,commit);pump(.03)
    committed=json.loads(invoke('inputStyle'))
    assert committed['preedit']=='' and committed['color']=='#f0e2c6' and committed['background']=='#10191b',committed
    assert '无懈' in committed['text'],committed
    if not args.measure_only:
        invoke('failRead');pump(.01);assert state()['count']==0,state()
        invoke('recoverRead');pump(.01);assert state()['count']==300,state()
    invoke('openKnown');pump(.03)
    known=window.findChild(QObject,'counterKnownList');assert known and known.property('count')==1
    invoke('knownTop');pump(.03);assert known.property('count')==1
    window.grabWindow().save(str(args.work_dir/'known-cards.png'))
    invoke('knownEmpty');pump(.03);assert known.property('count')==0
    invoke('close');closed=state();pump(.6);assert state()['reads']==closed['reads'],'hidden counter must not poll'
    result={'generated_cards':generated,'removed_generated_cards':removed,'initial':initial,'after_live_counts':updated,'during_flick_start':start,'during_flick_end':moving,'after_flick':stopped,
      'delegates_created_by_count_updates':updated['creates']-initial['creates'],'snapshots_during_flick':moving['reads']-start['reads'],
      'input_geometry':input_geometry,'input_composing':composing,'input_committed':committed,'qml_errors':[m for m in logs if any(e in m for e in ['TypeError','ReferenceError','SyntaxError','Cannot assign','is not a type'])]}
    if not args.measure_only:
        assert not result['qml_errors'],result['qml_errors']
        assert result['delegates_created_by_count_updates']==0,result
        assert start['moving'] and moving['moving'],result
        assert result['snapshots_during_flick']==0,result
        assert stopped['reads']>moving['reads'],result
        assert input_geometry['y']>=0 and 0<input_geometry['height'] and input_geometry['y']+input_geometry['height']<=input_geometry['fieldHeight']+1,input_geometry

    if args.lua_library:
        directory=os.add_dll_directory(str(Path(args.lua_library).resolve().parent)) if os.name=='nt' else None
        lib=ctypes.CDLL(args.lua_library);lib.luaL_newstate.restype=ctypes.c_void_p
        lib.luaL_openlibs.argtypes=[ctypes.c_void_p];lib.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
        lib.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ctypes.c_void_p]
        lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
        lib.lua_close.argtypes=[ctypes.c_void_p]
        script='local M=assert(load('+json.dumps((args.payload/'card-counter/counter.lua').read_text(encoding='utf8'),ensure_ascii=False)+',"counter.lua"))()\n'+r'''
local cards,pool={},{}
for id=1,900 do pool[id]=true;cards[id]={name="c"..math.floor((id-1)/3),type=id%3+1,suit=id%4+1,number=id%13+1} end
local viewer={id=1,player_cards={[1]={1,2,3}},card_tracker={void={known_cards={26}}}}
function viewer:cardVisible(id) return id<24 end
local room={_counter_pool=pool,card_place={},players={viewer},discard_pile={11,12,13},processing_area={21,22}}
room.draw_pile=setmetatable({},{__index=function() error("hidden deck accessed") end,__pairs=function() error("hidden deck enumerated") end})
local engine={getCardById=function(_,id) return cards[id] end,translate=function(_,key) return key end}
local all=M.snapshot(room,engine,viewer)
local one=M.snapshot(room,engine,viewer,"c17")
for _,field in ipairs({"total","unseen","known","discard","hand"}) do assert(all[field]==one[field],field) end
local detailRows=0
for i,row in ipairs(one.rows) do
 local old=all.rows[i];assert(row.key==old.key)
 for _,field in ipairs({"total","unseen","known","discard","hand"}) do assert(row[field]==old[field],field) end
 if next(row.details) then detailRows=detailRows+1;assert(row.key=="c17")
  for field,d in pairs(row.details) do for j,n in ipairs(d.points) do assert(n==old.details[field].points[j]) end end
 end
end
assert(detailRows==1,"only selected row needs suit/rank details")
-- Only the viewer's known/uncertain tracker and public visible cards feed the
-- record view. Poisoned hidden deck/hand access remains forbidden.
local target={id=2,screenName="target",player_cards={[1]={27,28,29}}}
room.players={viewer,target}
viewer.card_tracker.player_cards={[2]={[1]={known_cards={27},uncertain_cards={28}}}}
viewer.card_tracker.draw_pile_order={31,32,-1,-1,33}
local k=M.snapshot(room,engine,viewer).knowledge
assert(#k.hands==2 and k.hands[1].id==27 and not k.hands[1].uncertain and k.hands[2].uncertain)
assert(#k.top==2 and k.top[1].id==31 and k.top[2].position==2)
assert(#k.bottom==1 and k.bottom[1].id==33 and k.bottom[1].position==1)
viewer.card_tracker.player_cards[2][1]={known_cards={},uncertain_cards={27}}
viewer.card_tracker.draw_pile_order={}
k=M.snapshot(room,engine,viewer).knowledge
assert(#k.hands==1 and k.hands[1].uncertain and #k.top==0 and #k.bottom==0)
-- Private reveal capture accepts actual visible IDs and writes only the
-- viewer's tracker; the normal move tracker owns subsequent uncertainty.
Card={PlayerHand=1,Processing=5,DrawPile=6}
Self=viewer;ClientInstance=room
local remembered={}
function room:getCardArea(id) return ({[27]=1,[31]=5,[32]=6,[33]=4})[id] end
function room:getCardOwner(id) return id==27 and target or nil end
function viewer.card_tracker:setCardKnown(id,owner,area)
 remembered[#remembered+1]={id=id,owner=owner,area=area}
end
assert(M.remember({27,31,32,33,-1}))
assert(#remembered==3 and remembered[1].owner==target and remembered[3].area==6)

return "counts, selected details and hidden-zone restrictions passed; detail rows 300 -> "..detailRows
'''
        bootstrap=(args.payload/'card-counter/bootstrap.lua').read_text(encoding='utf8')
        script=script.replace('return "counts, selected details', 'local snapshotResult="counts, selected details')
        script+='\nlocal install=assert(load('+json.dumps(bootstrap,ensure_ascii=False)+',"bootstrap.lua"))\n'+r'''
Client={prepareDrawPile=function() end,deserialize=function() end,
 shuffleDrawPile=function(self,ids) self.shuffles=(self.shuffles or 0)+1;self.draw_pile=ids;return "shuffled" end}
Fk={boardgames={}}
install();install()
local hand={known_cards={27},uncertain_cards={28}}
local tracker={draw_pile_order={31,-1,32},draw_pile={known_cards={31,32}},player_cards={[2]={[1]=hand}}}
local room=setmetatable({players={{card_tracker=tracker}}},{__index=Client})
assert(room:shuffleDrawPile({32,31})=="shuffled" and room.shuffles==1)
assert(#tracker.draw_pile_order==0 and #tracker.draw_pile.known_cards==0)
assert(tracker.player_cards[2][1]==hand and hand.known_cards[1]==27)
return snapshotResult.."; visible reveal and shuffle invalidation passed"
'''
        vm=lib.luaL_newstate()
        try:
            lib.luaL_openlibs(vm)
            assert lib.luaL_loadstring(vm,script.encode())==0,lib.lua_tolstring(vm,-1,None)
            assert lib.lua_pcallk(vm,0,1,0,0,None)==0,lib.lua_tolstring(vm,-1,None)
            result['lua']=lib.lua_tolstring(vm,-1,None).decode()
        finally:
            lib.lua_close(vm)
            if directory:directory.close()
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if args.result:args.result.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    engine.deleteLater();app.processEvents()
