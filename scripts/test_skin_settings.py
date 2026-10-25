# Large skin catalogue responsiveness and download ownership in real QML.
import argparse,json,os,shutil,tempfile,time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen');os.environ.setdefault('QT_QUICK_BACKEND','software')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);a=p.parse_args()
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
with tempfile.TemporaryDirectory() as t:
 b=Path(t)
 def put(n,s):
  f=b/n;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(s,encoding='utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Lua','Cpp','Fs','Backend']))
 put('Fk/Lua.qml',r'''pragma Singleton
import QtQuick
QtObject {
 function createComponent(spec){return Qt.createComponent("Original.qml");}
 function tr(s){return s;}
 function evaluate(s){const out=[];for(let i=0;i<4000;i++)out.push({path:"https://skin/",name:"skin"+i,is_skel:i===0,files:["a","b","c"]});return out;}
}''')
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject {property string path:"/fixture"}')
 put('Fk/Fs.qml',r'''pragma Singleton
import QtQuick
QtObject {property int checks:0;property var downloads:[];
 function resolveFile(p){checks++;return p.endsWith("/a");}
 function downloadFileToAssets(url,dest){downloads=downloads.concat([dest]);}
}''')
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject {signal assetsDownloadFinished(bool ok,string path,string error)}')
 put('Fk/Widgets/qmldir','module Fk.Widgets\nPageBase 1.0 PageBase.qml\n');put('Fk/Widgets/PageBase.qml','import QtQuick\nItem {}')
 put('Fk/Components/Common/qmldir','module Fk.Components.Common\nLogEdit 1.0 LogEdit.qml\n');put('Fk/Components/Common/LogEdit.qml','import QtQuick\nItem {function append(v){}}')
 put('LunarLtk/qmldir','module LunarLtk\nsingleton Ltk 1.0 Ltk.qml');put('LunarLtk/Ltk.qml','pragma Singleton\nimport QtQuick\nQtObject {function urlToBase62(s){return "hash";}}')
 put('Fk/Original.qml','import QtQuick\nItem {}')
 shutil.copy2(a.payload/'card-counter/SkinSetting.qml',b/'SkinSetting.qml')
 routing=(a.payload/'card-counter/CounterHost.qml').read_text(encoding='utf8')
 routing=routing[routing.index('  function prepareSkinMenu('):routing.index('  // Follow the stock StackView')]
 put('Main.qml',r'''import QtQuick
import Fk
Window {id:host;width:900;height:500;visible:true
 ROUTING
 ListModel {id:menu}
 Component.onCompleted: menu.append({pkname:"core",pages:[{qml:{uri:"LunarLtk.Pages",name:"SkinSetting"}},{qml:{uri:"other",name:"Other"}}]})
 function route(){prepareSkinMenu(menu);return JSON.stringify({skin:menu.get(0).pages.get(0).qml.url,other:menu.get(0).pages.get(1).qml.name});}
 property int pulses:0
 Timer {interval:1;repeat:true;running:true;onTriggered:host.pulses++}
 SkinSetting {id:skins;objectName:"skins";anchors.fill:parent}
 function state(){return JSON.stringify({scanning:skins.scanning,index:skins.scanIndex,missing:skins.unsolvedSkins.length,checks:Fs.checks,pulses:pulses,active:skins.activeCount,downloads:Fs.downloads});}
 function start(){skins.startDownloadArray();}
 function unrelated(){Backend.assetsDownloadFinished(true,"unrelated","ignore");}
 function complete(){Backend.assetsDownloadFinished(true,Fs.downloads[0],"");}
}'''.replace('ROUTING',routing))
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs
 win=engine.rootObjects()[0]
 def pump(ms):
  loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def call(n):QMetaObject.invokeMethod(win,n)
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 raw=QMetaObject.invokeMethod(win,'route',Q_RETURN_ARG('QVariant'));assert raw,logs
 route=json.loads(raw)
 assert route['skin']=='card-counter/SkinSetting.qml' and route['other']=='Other',route
 pump(5);initial=state();assert initial['scanning'] and initial['index']<4000,initial
 until=time.monotonic()+10
 while state()['scanning'] and time.monotonic()<until:pump(5)
 done=state();assert not done['scanning'] and done['missing']==4000 and done['checks']==4001,done
 assert done['pulses']>20,done
 call('unrelated');assert state()['active']==0
 call('start');started=state();assert started['active']==5 and len(started['downloads'])==5,started
 call('unrelated');assert state()==started
 call('complete');assert state()['active']==5 and len(state()['downloads'])==6
 call('complete');assert len(state()['downloads'])==6,'duplicate completion must not create another worker'
 errors=[m for m in logs if any(v in m for v in ['TypeError','ReferenceError','Binding loop','is not a type','Cannot assign'])];assert not errors,errors
 print(json.dumps({'skin_count':4000,'file_checks':done['checks'],'event_loop_pulses_during_scan':done['pulses'],'partial_skeleton_detected':True,'download_concurrency':5,'foreign_and_duplicate_signals_ignored':True,'errors':errors}))
 win.close();engine.deleteLater();app.processEvents()
