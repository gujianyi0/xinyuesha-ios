# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise real typed PhotoModel lists and mark delegates across repeated updates."""
from pathlib import Path
import json,os,re,shutil,tempfile,time
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QUrl,QMetaObject,Qt,Q_RETURN_ARG,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
R=Path(__file__).resolve().parents[1]/'runtime'
UI=Path(os.environ.get('FK_TEST_UI',R))
logs=[]
qInstallMessageHandler(lambda kind,context,message:logs.append(message))
app=QGuiApplication([])
workspace=tempfile.TemporaryDirectory(dir=os.environ.get('FK_TEST_TMP'))
B=Path(workspace.name)
def put(name,data):
 p=B/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(data,encoding='utf-8')
def copy(name,target):
 p=B/target;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(UI/name,p)
put('Fk/qmldir','module Fk\nsingleton Config 1.0 Config.qml\nsingleton Lua 1.0 Lua.qml\nsingleton SkinBank 1.0 SkinBank.qml\n')
put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property string libianName:"sans-serif";}')
put('Fk/SkinBank.qml','pragma Singleton\nimport QtQuick\nQtObject {function getMarkPic(name){return "";}}')
put('Fk/Lua.qml','''pragma Singleton
import QtQuick
QtObject {
 property var selfPlayer:({cardVisible:function(id){return id<5;}})
 property var currentCustom:({text:"初始",qml:{name:"ViewGeneralPile",prop:{cardNames:["first"]}}})
 function tr(s){return String(s);}
 function getQmlMark(type,name,id){return currentCustom;}
}''')
put('Fk/Widgets/qmldir','module Fk.Widgets\nTapHandler 1.0 TapHandler.qml\n')
copy('Fk/Widgets/TapHandler.qml','Fk/Widgets/TapHandler.qml')
mark_source=(UI/'LunarLtk/LtkLuaUtil.qml').read_text(encoding='utf-8')
method=mark_source[mark_source.index('  function setMark('):mark_source.index('  function createCardModel(')]
put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml\nPhotoModel 1.0 PhotoModel.qml\nCardModel 1.0 CardModel.qml\n')
put('LunarLtk/Ltk.qml','''pragma Singleton
import QtQuick
import Fk
QtObject {
 property var pile:[1,2]
 function getPlayer(id){return {getPile:function(name){return pile;}};}
 function getTargetTip(id){return [];}
 METHOD
}'''.replace('METHOD',method))
put('LunarLtk/CardModel.qml','import QtQuick\nQtObject {}')
# Enum values belong to the native plugin; preserve the real list declarations
# and methods, substituting only those unrelated native enum constants.
photo=(UI/'LunarLtk/Models/PhotoModel.qml').read_text(encoding='utf-8')
put('LunarLtk/PhotoModel.qml',photo.replace('Ltk.General.Female','0').replace('Ltk.Player.NotActive','0'))
copy('LunarLtk/Components/Photo/MarkArea.qml','MarkArea.qml')
copy('LunarLtk/Components/Photo/PicMarkArea.qml','PicMarkArea.qml')
put('Main.qml','''import QtQuick
import Fk
import LunarLtk
Window {
 width:600;height:400;visible:true
 PhotoModel {id:photo;playerid:1}
 MarkArea {id:area;width:103;markModel:photo.marks}
 PicMarkArea {id:pics;y:220;markModel:photo.picMarks}
 function initial(){Ltk.setMark(photo.marks,"@诡伏",1,1);Ltk.setMark(photo.picMarks,"@!!图标",2,1);}
 function update(){Ltk.setMark(photo.marks,"@诡伏",4,1);Ltk.setMark(photo.picMarks,"@!!图标",5,1);}
 function listInitial(){Ltk.setMark(photo.marks,"@&化身",["甲","乙","丙"],1);}
 function listUpdate(){Ltk.setMark(photo.marks,"@&化身",["丁"],1);}
 function customInitial(){Ltk.setMark(photo.marks,"@[custom]化身",1,1);}
 function customUpdate(){Lua.currentCustom={text:"已换将",qml:{name:"ViewGeneralPile",prop:{cardNames:["second","third"]}}};Ltk.setMark(photo.marks,"@[custom]化身",2,1);}
 function pileInitial(){Ltk.setMark(photo.marks,"特殊牌堆",2,1);}
 function pileUpdate(){Ltk.pile=[3,4,5];Ltk.setMark(photo.marks,"特殊牌堆",3,1);}
 function remove(){for(const name of ["@诡伏","@&化身","@[custom]化身","特殊牌堆"])Ltk.setMark(photo.marks,name,0,1);Ltk.setMark(photo.picMarks,"@!!图标",0,1);}
 function readd(){Ltk.setMark(photo.marks,"@诡伏",7,1);}
 function inspect(){
   const rep=Array.from(area.children).find(c=>typeof c.itemAt==="function");
   const texts=[];for(let i=0;i<rep.count;i++)texts.push(rep.itemAt(i).children[0].text);
   const picRep=Array.from(pics.children).find(c=>typeof c.itemAt==="function");
   return JSON.stringify({model:Array.from(photo.marks),texts:texts,picModel:Array.from(photo.picMarks),picText:picRep.count?picRep.itemAt(0).children[1].text:null});
 }
}''')
engine=QQmlApplicationEngine();engine.addImportPath(str(B));engine.load(QUrl.fromLocalFile(str(B/'Main.qml')))
assert engine.rootObjects(),logs
window=engine.rootObjects()[0]
def pump():
 until=time.monotonic()+.06
 while time.monotonic()<until:app.processEvents();time.sleep(.002)
def call(name):
 QMetaObject.invokeMethod(window,name,Qt.DirectConnection);pump()
 return json.loads(QMetaObject.invokeMethod(window,'inspect',Qt.DirectConnection,Q_RETURN_ARG('QVariant')))
states={name:call(name) for name in ['initial','update','listInitial','listUpdate','customInitial','customUpdate','pileInitial','pileUpdate','remove','readd']}
print(json.dumps({'states':states,'logs':logs},ensure_ascii=False,indent=2))
assert states['initial']['texts']==['@诡伏 1']
assert states['update']['texts']==['@诡伏 4'],'numeric mark must update existing delegate'
assert states['update']['picText']=='5','picture mark number must update'
assert '5' in states['update']['picModel'][0]['desc'],'picture description must update'
assert states['listUpdate']['model'][1]['qml']['prop']['cardNames']==['丁'],'mark popup must use current general list'
assert states['listUpdate']['texts'][1]=='@&化身 1'
assert states['customUpdate']['texts'][2]=='@[custom]化身 已换将'
assert states['customUpdate']['model'][2]['qml']['prop']['cardNames']==['second','third']
assert states['pileUpdate']['texts'][3]=='特殊牌堆 3'
assert states['pileUpdate']['model'][3]['qml']['prop']['ids']==[3,4],'only visible pile cards enter popup'
assert states['remove']['texts']==[] and states['remove']['picText'] is None
assert states['readd']['texts']==['@诡伏 7']
assert not [m for m in logs if any(x in m for x in ['TypeError','ReferenceError','SyntaxError','Unable to assign','Cannot assign','Binding loop'])],logs
window.close();engine.deleteLater();app.processEvents()
