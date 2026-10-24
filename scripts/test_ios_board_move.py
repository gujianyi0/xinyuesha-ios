# SPDX-License-Identifier: GPL-3.0-or-later
"""Real board-move QML and pointer selection on the shipped Qt version."""
import os,json,tempfile,shutil,time,argparse
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QObject,QUrl,QMetaObject,Q_RETURN_ARG,Qt,QPoint,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from PySide6.QtQuick import QQuickItem,QQuickWindow
p=argparse.ArgumentParser();p.add_argument('--expect-empty',action='store_true');a=p.parse_args()
C=Path(__file__).resolve().parents[1];UI=Path(os.environ.get('FK_TEST_UI',C/'runtime'));logs=[]
qInstallMessageHandler(lambda kind,ctx,msg:logs.append(msg));app=QGuiApplication([])
with tempfile.TemporaryDirectory() as t:
 B=Path(t)
 def put(n,s):
  p=B/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\nsingleton Config 1.0 Config.qml\nsingleton Lua 1.0 Lua.qml\n')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property string libianName:"sans-serif";}')
 put('Fk/Lua.qml','pragma Singleton\nimport QtQuick\nQtObject {function tr(s){return String(s);}}')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\n')
 put('LunarLtk/Ltk.qml',"pragma Singleton\nimport QtQuick\nQtObject {function getVirtualEquipData(p,id){return {name:'virtual_'+id};}function createCardModel(id,props){return {cardId:id,subtype:'weapon',virtName:props.virtName};}function getPlayerStr(id){return 'Player '+id;}function processPrompt(s){return s;}}")
 put('Fk/Components/Common/qmldir','module Fk.Components.Common\nPoxiLabel 1.0 PoxiLabel.qml\nMetroButton 1.0 MetroButton.qml\n')
 put('Fk/Components/Common/PoxiLabel.qml','import QtQuick\nText {objectName:"ownerLabel";width:70;height:30}')
 put('Fk/Components/Common/MetroButton.qml','import QtQuick.Controls\nButton {objectName:"boardConfirm"}')
 put('LunarLtk/Components/qmldir','module LunarLtk.Components\nCardItem 1.0 CardItem.qml\n')
 put('LunarLtk/Components/CardItem.qml',"import QtQuick\nRectangle {objectName:'boardCard';width:93;height:130;property var dataModel;property bool selectable;property real origX;property real origY;signal clicked();function goBack(animated){x=origX;y=origY;}MouseArea {anchors.fill:parent;onClicked:parent.clicked();}}")
 put('LunarLtk/Models/Popups/qmldir','module LunarLtk.Models.Popups\nMoveCardInBoardModel 1.0 MoveCardInBoardModel.qml\n')
 shutil.copyfile(UI/'LunarLtk/Models/Popups/MoveCardInBoardModel.qml',B/'LunarLtk/Models/Popups/MoveCardInBoardModel.qml')
 for f in ['GraphicsBox.qml','MoveCardInBoardBox.qml']:shutil.copyfile(UI/'LunarLtk/Pages/Popups'/f,B/f)
 put('Main.qml',"""import QtQuick
import LunarLtk.Models.Popups
Window {id:win;width:1000;height:600;visible:true
 property var board:null;property var move:null;property var packets:[]
 function setup(){const ids=[101,102,103],positions=[0,1,0];move=Qt.createComponent('LunarLtk.Models.Popups','MoveCardInBoardModel').createObject(win,{cardIds:ids,cardsPosition:positions,playerIds:[11,12]});move.accepted.connect(()=>{packets=packets.concat([{cardId:move.result,pos:positions[ids.indexOf(move.result)]}]);});board=Qt.createComponent('MoveCardInBoardBox.qml').createObject(win.contentItem,{dataModel:move,x:20,y:20});board.shown();}
 function state(){return JSON.stringify({ids:Array.from(move.cardIds),positions:Array.from(move.cardsPosition),players:Array.from(move.playerIds),width:board.width,height:board.height,selected:move.result,feasible:move.feasible,packets:packets});}
}""")
 engine=QQmlApplicationEngine();engine.addImportPath(str(B));engine.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert engine.rootObjects(),logs
 win=engine.rootObjects()[0]
 def pump():
  until=time.monotonic()+.2
  while time.monotonic()<until:app.processEvents();time.sleep(.005)
 QMetaObject.invokeMethod(win,'setup',Qt.DirectConnection);pump()
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Qt.DirectConnection,Q_RETURN_ARG('QVariant')))
 board=win.property('board')
 if hasattr(board,'toQObject'):board=board.toQObject()
 def visual_items(item):
  result=[item]
  for child in item.childItems():result+=visual_items(child)
  return result
 items=visual_items(board);cards=[c for c in items if c.objectName()=='boardCard'];s=state();s['card_count']=len(cards)
 if a.expect_empty:
  assert len(cards)==0, (s,logs)
 else:
  assert len(cards)==3 and s['players']==[11,12] and s['width']>=340,(s,logs)
  assert len([c for c in items if c.objectName()=='ownerLabel'])==2
  chosen=next(c for c in cards if c.property('dataModel').toVariant()['cardId']==102)
  pos=chosen.mapToScene(__import__('PySide6.QtCore',fromlist=['QPointF']).QPointF(40,50));QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(pos.x()),round(pos.y())));pump()
  assert state()['selected']==102 and state()['feasible'],(state(),logs)
  confirm=next(c for c in items if c.objectName()=='boardConfirm');pos=confirm.mapToScene(__import__('PySide6.QtCore',fromlist=['QPointF']).QPointF(40,15));QTest.mouseClick(win,Qt.LeftButton,Qt.NoModifier,QPoint(round(pos.x()),round(pos.y())));pump()
  assert state()['packets']==[{'cardId':102,'pos':1}],(state(),logs)
 errors=[x for x in logs if any(v in x for v in ['TypeError','ReferenceError','Unable to assign','Cannot assign','Binding loop'])]
 if not a.expect_empty:assert not errors,errors
 print(json.dumps({'initial':s,'final':state(),'errors':errors},ensure_ascii=False))
 win.close();engine.deleteLater();app.processEvents()
