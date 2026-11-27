"""Real badge, PopupItem and ViewPile with deterministic card-data/render fixtures."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Basic')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,Q_ARG,QTimer,QEventLoop,QPointF,Qt,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--baseline',action='store_true');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1];source=(a.payload/'card-counter/CounterHost.qml').read_text('utf8');fragment=source[source.index('  Component {\n    id: knownHandBadgeComponent'):source.index('  property var guanNingPluginComponent:')]
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
font=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont(QFontDatabase.applicationFontFamilies(font)[0]))
with tempfile.TemporaryDirectory(dir=a.output) as temp:
 b=Path(temp)
 def put(name,value):
  path=b/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value,'utf8')
 put('Fk/qmldir','module Fk\nsingleton Lua 1.0 Lua.qml\nsingleton Config 1.0 Config.qml\n')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property real winScale:1;}')
 put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject{property var rows:[];property var cards:({1:{name:"杀",suit:"spade",number:7},2:{name:"杀",suit:"heart",number:11},3:{name:"无懈可击",suit:"club",number:13},4:{name:"南蛮入侵",suit:"diamond",number:1}})
 function ev(s){return {knowledge:{hands:rows}};}function tr(s){return s==="hand_card"?"明牌手牌":s;}}
''')
 put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\nPopupItem 1.0 PopupItem.qml\n')
 for name in ['TapHandler','PopupItem']:shutil.copyfile(root/'runtime/Fk/Widgets'/(name+'.qml'),b/'Fk/Widgets'/(name+'.qml'))
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
 put('LunarLtk/Ltk.qml','''pragma Singleton
import QtQuick
import Fk
QtObject{function createCardModel(id,props){return Object.assign({cardId:id},Lua.cards[id],props);}}
''')
 put('LunarLtk/Components/qmldir','module LunarLtk.Components\nCardItem 1.0 CardItem.qml\nBigGlowText 1.0 BigGlowText.qml\n')
 put('LunarLtk/Components/BigGlowText.qml','import QtQuick\nItem{property alias text:label.text;Text{id:label;font.pixelSize:22;}}')
 put('LunarLtk/Components/CardItem.qml','''import QtQuick
Rectangle{objectName:"cardDataFixture";width:93;height:130;color:"#f2ead6";border.color:"#222";property bool autoBack:false;property var dataModel
 Text{x:5;y:5;text:parent.dataModel.suit+" "+parent.dataModel.number;font.pixelSize:11}
 Text{anchors.centerIn:parent;text:parent.dataModel.name;font.pixelSize:15}}
''')
 put('LunarLtk/Pages/InfoPopups/qmldir','module LunarLtk.Pages.InfoPopups\nViewPile 1.0 ViewPile.qml\n')
 shutil.copyfile(root/'runtime/LunarLtk/Pages/InfoPopups/ViewPile.qml',b/'LunarLtk/Pages/InfoPopups/ViewPile.qml')
 put('HandcardViewer.qml','import QtQuick\nRectangle{width:44;height:112;color:"orange";}')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
import Fk.Widgets as W
Window{id:win;width:800;height:500;visible:true;color:"#263339"
 Item{id:scene;anchors.fill:parent;property string seenProps:"";property alias infoPopup:info;property var dataModel:({players:[{id:2,photoItem:photo},{id:3,photoItem:other}]})
  Rectangle{id:photo;x:300;y:140;width:120;height:145;color:"#557766";clip:true;HandcardViewer{}}
  Rectangle{id:other;x:650;y:140;width:120;height:145;color:"#445588";clip:true;HandcardViewer{}}
  W.PopupItem{id:info;width:480;height:380;anchors.centerIn:parent}
  function showInfoPopup(component,props){seenProps=JSON.stringify(props);info.setSourceComponent(component,props);info.open();}
 }
 Item{id:host;property var currentScene:scene;property var knownHandBadges:[];property var knownHandCounts:({});property string knownHandPayload:""
  property var knownHandPopupItem:null;property var knownHandPopupControl:null;property string knownHandPopupOwner:"";property var knownHandPopupIds:[]
  onCurrentSceneChanged:closeKnownHandPopup()
  function disposeRoomItem(item){if(item)item.destroy();}function triggerGuanNingSkinEffects(p){}
  FRAGMENT
 }
 function update(rows){Lua.rows=rows;host.syncKnownHandBadges();}
 function expire(){update([{ownerId:3,id:1,name:"杀",suit:1,number:7}]);}
 function reduce(){update([{ownerId:2,id:3,name:"无懈可击",suit:2,number:13},{ownerId:2,id:4,name:"南蛮入侵",suit:4,number:1},{ownerId:3,id:1,name:"杀",suit:1,number:7}]);}
 function stale(){host.openKnownHands([1,2,3,4],"2");}
 function close(){info.close();}
 function position(x){photo.x=x;host.syncKnownHandBadges();}
 function leave(){host.currentScene=null;}
 function models(){const grid=info.item&&Array.from(info.item.children).find(c=>"cellWidth" in c);return JSON.stringify({count:grid?grid.count:-1,models:grid?Array.from(grid.contentItem.children).filter(c=>c.objectName==="cardDataFixture").map(c=>c.dataModel):[]});}
 function state(){const badge=host.knownHandBadges.find(b=>b.photo===photo);return JSON.stringify({open:info.visible,props:scene.seenProps,saved:host.knownHandPopupIds,item:String(info.item),popupName:info.item?info.item.name:"",rawIds:info.item?JSON.stringify(info.item.ids):"",idLength:info.item?info.item.ids.length:0,ids:info.item?Array.from(info.item.ids):[],cards:badge?badge.knownCards:[],rows:badge?badge.knownRows:[],badge:badge?{x:badge.x,y:badge.y,width:badge.width,height:badge.height}:null});}
}'''.replace('FRAGMENT',fragment))
 engine=QQmlApplicationEngine();engine.addImportPath(str(b.resolve()));engine.rootContext().setContextProperty('ClientInstance',app);engine.load(QUrl.fromLocalFile(str((b/'Main.qml').resolve())));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump(ms=100):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def action(name,*args):QMetaObject.invokeMethod(win,name,*[Q_ARG('QVariant',v) for v in args]);pump()
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 rows=[dict(ownerId=2,id=i+1,name=name,suit=suit,number=number) for i,(name,suit,number) in enumerate([('杀',1,7),('杀',3,11),('无懈可击',2,13),('南蛮入侵',4,1)])]+[dict(ownerId=2,id=5,name='未知牌',uncertain=True),dict(ownerId=3,id=6,name='桃')]
 action('update',rows);assert state()['cards']==['杀','杀','无懈可击','南蛮入侵'],(state(),logs)
 def click(touch=False):
  badges=win.findChildren(QQuickItem,'knownHandBadge');badge=badges[0] if a.baseline else next(item for item in badges if item.property('ownerKey')=='2');point=badge.mapToScene(QPointF(badge.width()/2,badge.height()/2)).toPoint()
  if touch:
   device=QTest.createTouchDevice();QTest.touchEvent(win,device).press(0,point,win).commit();pump(40);QTest.touchEvent(win,device).release(0,point,win).commit()
  else:QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,point)
  pump(250)
 win.grabWindow().save(str(a.output/'side-list.png'));click()
 if a.baseline:
  report=dict(qt=__import__('PySide6').__version__,requestedIds=[1,2,3,4],actualIds=state()['ids'],popupVisible=state()['open'],cardGrid=json.loads(QMetaObject.invokeMethod(win,'models',Q_RETURN_ARG('QVariant'))),physicalDevice=False)
  (a.output/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8');print(json.dumps(report,ensure_ascii=False));raise SystemExit(0)
 assert state()['open'] and state()['ids']==[1,2,3,4],(state(),logs)
 grid=json.loads(QMetaObject.invokeMethod(win,'models',Q_RETURN_ARG('QVariant')));models=grid['models']
 assert {(m['cardId'],m['suit'],m['number']) for m in models}=={(1,'spade',7),(2,'heart',11),(3,'club',13),(4,'diamond',1)},models
 assert all(m['known'] for m in models),models
 win.grabWindow().save(str(a.output/'expanded-cards.png'));action('reduce');assert state()['ids']==[3,4],state();action('expire');assert not state()['open'],state()
 action('stale');assert not state()['open'],state();action('update',rows);click(True);assert state()['open'] and state()['ids']==[1,2,3,4],(state(),logs);action('close')
 for x in [0,55,300,680]:
  action('position',x);rect=state()['badge'];assert 0<=rect['x'] and rect['x']+rect['width']<=win.width() and (rect['x']+rect['width']<=x or rect['x']>=x+120),state()
 click();assert state()['open'];action('leave');assert not state()['open'],state()
 errors=[m for m in logs if any(s in m for s in ['TypeError','ReferenceError','Cannot assign','Unable to assign','Binding loop','Error:'])];assert not errors,errors
 report=dict(passed=True,qt=__import__('PySide6').__version__,actualBadgePopupAndViewPile=True,mouseAndTouchOpenFourExactCards=True,duplicateNamesKeepSuitAndNumber=True,uncertainAndOtherOwnerExcluded=True,openPopupExpiresOnMoves=True,edgePortraitsNotOverlapped=True,cardDataAndRenderingFixture=True,physicalDevice=False)
 (a.output/'result.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report));win.close()
