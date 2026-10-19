"""Exercise the actual counter while a large catalogue updates and flicks."""
import argparse, ctypes, ctypes.util, json, os, shutil, tempfile, time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QEvent, QEventLoop, QTimer, QUrl, QMetaObject, Q_RETURN_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir',type=Path,required=True)
parser.add_argument('--payload',type=Path,default=Path(__file__).resolve().parents[1]/'runtime')
parser.add_argument('--measure-only',action='store_true')
parser.add_argument('--result',type=Path)
parser.add_argument('--lua-library')
args=parser.parse_args();args.work_dir.mkdir(parents=True,exist_ok=True)
logs=[];qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg))
app=QGuiApplication([])

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
Window {
 id:win;width:1200;height:540;visible:true
 property int tick:0;property int reads:0
 property bool failSnapshot:false
 function sample(){
  const rows=[];
  for(let i=0;i<300;i++){
   let points=Array(70).fill(0);points[1]=1;
   let details={unseen:{suits:[1,0,0,0,0],points:points},discard:{suits:[0,0,0,0,0],points:Array(70).fill(0)},hand:{suits:[0,0,0,0,0],points:Array(70).fill(0)}};
   rows.push({key:"c"+i,name:"卡牌"+i,kind:i%3+1,total:3,unseen:i===17?tick%2:3,hand:0,discard:0,details:details});
  }
  return {ready:true,rows:rows,total:900,unseen:900-tick%2,hand:0,discard:0};
 }
 CardCounter {id:counter;selectedKey:"c17";readSnapshot:function(){win.reads++;if(win.failSnapshot) throw new Error("fixture snapshot unavailable");return win.sample();};cardPicture:function(n){return "";}}
 function open(){counter.open();}
 function close(){counter.close();}
 function change(){tick++;counter.refresh();}
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
 function inputGeometry(){const field=counter.testSearch;const cursor=field.cursorRectangle;return JSON.stringify({y:cursor.y,height:cursor.height,fieldHeight:field.height,topPadding:field.topPadding,bottomPadding:field.bottomPadding});}
 function state(){return JSON.stringify({reads:reads,creates:counter.testCreates,count:counter.rows.length,gridCount:counter.testGrid.count,moving:counter.testGrid.moving,y:counter.testGrid.contentY,selected:counter.selectedRow?counter.selectedRow.key:"",amount:counter.selectedRow?counter.selectedRow.unseen:-1});}
}''')
    engine=QQmlApplicationEngine();engine.addImportPath(str(base));engine.load(QUrl.fromLocalFile(str(base/'Main.qml')))
    assert engine.rootObjects(),logs
    window=engine.rootObjects()[0]
    def invoke(name):return QMetaObject.invokeMethod(window,name,Q_RETURN_ARG('QVariant'))
    def state():return json.loads(invoke('state'))
    invoke('open');pump(.08);initial=state();assert initial['count']==300,initial
    for _ in range(20):invoke('change');pump(.01)
    updated=state();invoke('startFlick');pump(.05);start=state();pump(.7);moving=state()
    invoke('stopFlick');pump(.1);stopped=state()
    invoke('hideZero');pump(.02);assert state()['count']==299,state()
    invoke('change');pump(.02);assert state()['count']==300,state()
    invoke('showZero');invoke('choose');pump(.02);assert state()['selected']=='c18',state()
    invoke('search');pump(.02);assert state()['count']==11,state()
    invoke('clearSearch');pump(.02);assert state()['count']==300,state()
    invoke('focusSearch');pump(.02);raw_geometry=invoke('inputGeometry');assert raw_geometry,logs
    input_geometry=json.loads(raw_geometry)
    if not args.measure_only:
        invoke('failRead');pump(.01);assert state()['count']==0,state()
        invoke('recoverRead');pump(.01);assert state()['count']==300,state()
    invoke('close');closed=state();pump(.6);assert state()['reads']==closed['reads'],'hidden counter must not poll'
    result={'initial':initial,'after_live_counts':updated,'during_flick_start':start,'during_flick_end':moving,'after_flick':stopped,
      'delegates_created_by_count_updates':updated['creates']-initial['creates'],'snapshots_during_flick':moving['reads']-start['reads'],
      'input_geometry':input_geometry,'qml_errors':[m for m in logs if any(e in m for e in ['TypeError','ReferenceError','SyntaxError','Cannot assign','is not a type'])]}
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
return "counts, selected details and hidden-zone restrictions passed; detail rows 300 -> "..detailRows
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
