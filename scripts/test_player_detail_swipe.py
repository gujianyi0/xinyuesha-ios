"""Real stock PlayerDetail + production adapter: touch, vertical scrolling and tab sync."""
import argparse, json, os, shutil, tempfile
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE','Material')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QPoint,QPointF,Qt,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--host',type=Path);p.add_argument('--work-dir',type=Path,required=True);p.add_argument('--baseline',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];a.work_dir.mkdir(parents=True,exist_ok=True)
host=(a.host or root/'runtime/card-counter/CounterHost.qml').read_text(encoding='utf8')
start=host.index('  // FB-0DX3XM:')
end=host.index('  function adaptPlayerDetail(item)',start)
adapter=host[start:end]
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
def pump(ms=150):
    loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
    b=Path(tmp)
    def put(name,text):
        f=b/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf8')
    put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Lua']))
    put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"iOS";property var self:({id:1});property bool quickStartMode:false;}')
    put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property bool observing:false;property bool hideScreenName:false;property bool banChangeSkin:false;property var blockedUsers:[];}')
    put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject{property var selfPlayer:({id:1,cardVisible:function(){return true;}})
 function tr(s){return s;}function getPlayerGameData(){return [10,5,0,3600];}
 function ev(){return null;}function evaluate(){return "";}}
''')
    put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
    put('LunarLtk/Ltk.qml','''pragma Singleton
import QtQuick
QtObject{
 property var roomScene:({dataModel:{dashboardId:1}})
 function createGeneralCardModel(){return {};}
 function getPlayer(){return {getCardIds:function(){return [1];},getVirtualEquip:function(){return null;}};}
 function getPlayerSkills(){return [{orig_name:"skill",name:"Skill",description:"Long skill description ".repeat(300),related_skills:[]}];}
 function getCardData(){return {};}
 function getCard(){return {toLogString:function(){return "Card";},getDynamicDescription:function(){return "Equipment description ".repeat(200);}};}
 function getSkinNamesByGeneral(){return [];}}
''')
    put('LunarLtk/Models/qmldir','module LunarLtk.Models\nPhotoModel 1.0 PhotoModel.qml\n')
    put('LunarLtk/Models/PhotoModel.qml','import QtQuick\nQtObject{property int playerid:2;property string avatar:"";property string general:"";property string deputyGeneral:"";property string screenName:"Test player";property int seatNumber:2;}')
    put('LunarLtk/Components/qmldir','module LunarLtk.Components\nGeneralCardItem 1.0 GeneralCardItem.qml\nDescriptionText 1.0 DescriptionText.qml\n')
    put('LunarLtk/Components/GeneralCardItem.qml','import QtQuick\nRectangle{implicitWidth:80;implicitHeight:110;color:"#345";property var dataModel;}')
    shutil.copy2(root/'runtime/LunarLtk/Components/DescriptionText.qml',b/'LunarLtk/Components/DescriptionText.qml')
    put('Fk/Components/Common/qmldir','module Fk.Components.Common\nAvatar 1.0 Avatar.qml\nMetroButton 1.0 MetroButton.qml\n')
    put('Fk/Components/Common/Avatar.qml','import QtQuick\nItem{property string general;}')
    put('Fk/Components/Common/MetroButton.qml','import QtQuick.Controls\nButton{}')
    put('Fk/Widgets/qmldir','module Fk.Widgets\nViewSwitcher 1.0 ViewSwitcher.qml\nTapHandler 1.0 TapHandler.qml\n')
    for n in ['ViewSwitcher','TapHandler']:shutil.copy2(root/('runtime/Fk/Widgets/'+n+'.qml'),b/('Fk/Widgets/'+n+'.qml'))
    shutil.copy2(root/'runtime/LunarLtk/Pages/InfoPopups/PlayerDetail.qml',b/'PlayerDetail.qml')
    put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import LunarLtk.Models
Window{id:win;width:1000;height:650;visible:true
 Item{id:host
 ADAPTER
 }
 PhotoModel{id:model}
 Item{id:frame;x:30;y:20;width:930;height:600
  Loader{id:loader;anchors.fill:parent;sourceComponent:Component{PlayerDetail{dataModel:model}}}
 }
 function install(){host.adaptPlayerDetailSwipe(loader.item);}
 function nodes(){const p=[loader.item],out=[];while(p.length){const n=p.pop();if(!n)continue;out.push(n);if(n.children)p.push(...Array.from(n.children));}return out;}
 function view(){return nodes().find(n=>String(n).indexOf("SwipeView_QMLTYPE")===0);}
 function tabs(){return nodes().find(n=>String(n).indexOf("ViewSwitcher_QMLTYPE")===0);}
 function state(){const v=view(),t=tabs(),p=v.mapToItem(win.contentItem,0,0);return JSON.stringify({page:v.currentIndex,tab:t.currentIndex,interactive:v.interactive,x:p.x,y:p.y,w:v.width,h:v.height,scroll:v.currentItem.contentY,syncs:Array.from(loader.item.children).filter(n=>n&&n.objectName==="playerDetailSwipeSync").length});}
 function setTab(i){tabs().currentIndex=i;}
 function reset(){loader.active=false;loader.active=true;}
 function narrow(){frame.width=700;frame.height=500;}
 function desktop(){Cpp.os="Windows";}
}'''.replace('ADAPTER',adapter))
    engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')))
    assert engine.rootObjects(),logs
    win=engine.rootObjects()[0]
    def call(name,*args):return QMetaObject.invokeMethod(win,name,Qt.DirectConnection,*[Q_ARG('QVariant',v) for v in args])
    def state():
        s=QMetaObject.invokeMethod(win,'state',Qt.DirectConnection,Q_RETURN_ARG('QVariant'));return json.loads(s)
    pump();assert not state()['interactive'],state()
    if not a.baseline:call('install');pump()
    device=QTest.createTouchDevice()
    def swipe(dx,dy=0):
        s=state();x=int(s['x']+s['w']*(.78 if dx<0 else .22));y=int(s['y']+s['h']*.55)
        q=QTest.touchEvent(win,device);q.press(0,QPoint(x,y),win).commit();pump(20)
        for step in range(1,11):
            q=QTest.touchEvent(win,device);q.move(0,QPoint(x+int(dx*step/10),y+int(dy*step/10)),win).commit();pump(20)
        q=QTest.touchEvent(win,device);q.release(0,QPoint(x+dx,y+dy),win).commit();pump(450)
    if a.baseline:
        swipe(-340);assert state()['page']==0,state();print(json.dumps({'baseline_horizontal_swipe_ignored':True}));raise SystemExit(0)
    checks=[]
    assert state()['interactive'] and state()['syncs']==1,state()
    for expected in [1,2,3]:swipe(-340);assert state()['page']==expected and state()['tab']==expected,state()
    swipe(-340);assert state()['page']==3,state();checks.append('left swipe through all four areas and last boundary')
    for expected in [2,1,0]:swipe(340);assert state()['page']==expected and state()['tab']==expected,state()
    swipe(340);assert state()['page']==0,state();checks.append('right swipe and first boundary')
    call('setTab',2);pump(450);assert state()['page']==2,state();checks.append('original tab selection stays connected')
    call('setTab',0);pump(450);swipe(0,-180);assert state()['scroll']>40 and state()['page']==0,state();checks.append('long skill text still scrolls vertically')
    for _ in range(4):call('install')
    assert state()['syncs']==1,state();checks.append('repeated adaptation installs exactly one connection')
    call('narrow');pump();call('setTab',0);pump(450);swipe(-260);assert state()['page']==1 and state()['tab']==1,state();checks.append('narrow resized panel')
    call('reset');pump();call('install');pump();assert state()['syncs']==1,state();swipe(-260);assert state()['page']==1,state();checks.append('close and reopen creates a fresh working adapter')
    call('reset');pump();call('desktop');call('install');pump();assert not state()['interactive'] and state()['syncs']==0,state();checks.append('non-iOS unchanged')
    errors=[s for s in logs if any(t in s for t in ['TypeError','ReferenceError','Binding loop','Cannot assign','Unable to assign'])]
    assert not errors,errors
    result={'checks':checks,'errors':errors,'qt':__import__('PySide6').__version__,'real_device':False}
    (a.work_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(result))
    win.close();engine.deleteLater();app.processEvents()
