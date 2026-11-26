"""Real stock manager + QML client: automatic activation survives page closure."""
import argparse,json,os,shutil,tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_QUICK_CONTROLS_STYLE='Material')
from PySide6.QtCore import QUrl,QTimer,QEventLoop,QMetaObject,Q_RETURN_ARG,Q_ARG,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QFontDatabase,QFont
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);root=Path(__file__).resolve().parents[1]
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
if Path('C:/Windows/Fonts/msyh.ttc').exists():i=QFontDatabase.addApplicationFont('C:/Windows/Fonts/msyh.ttc');app.setFont(QFont(QFontDatabase.applicationFontFamilies(i)[0]))
with tempfile.TemporaryDirectory(dir=a.output) as temp:
 b=Path(temp)
 def put(name,text):
  f=b/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,'utf8')
 put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Config','Backend','Fs','App']))
 put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string path:"file:///fixture";property string os:"Android";}')
 put('Fk/Fs.qml','pragma Singleton\nimport QtQuick\nQtObject{function isDir(path){return true;}function convertUrlToPath(path){return path;}}')
 put('Fk/App.qml','pragma Singleton\nimport QtQuick\nQtObject{function quitPage(){}}')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property var enabledResourcePacks:["other-pack"];property int saves:0;property string username:"fixture-user";property string password:"not-an-account";function saveConf(){saves++;}}')
 put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject {
 property var files:({});property var directories:["other-pack"]
 property var catalog:({schema:2,packs:[{id:"奶杀动皮-v1",title:"奶杀动皮（244款）",version:"fixture",bytes:1311839017},{id:"other-pack",title:"其他资源",version:"fixture",bytes:1000}]})
 function ls(path){return directories;}function readJsonObjectFromFile(path){return catalog;}
 function existsInAssets(path){return files[path]!==undefined;}
 function readFileFromAssets(path){return files[path]||"";}
 function writeFileToAssets(path,value){files[path]=value;return true;}
}''')
 put('Fk/Widgets/qmldir','module Fk.Widgets\nPageBase 1.0 PageBase.qml\n');shutil.copyfile(root/'runtime/Fk/Widgets/PageBase.qml',b/'Fk/Widgets/PageBase.qml')
 for name in ['ResourcePackClient.qml','ResourcePackDownload.qml']:shutil.copyfile(a.payload/'card-counter'/name,b/name)
 shutil.copyfile(root/'runtime/Fk/Pages/Common/ResourcePackManage.qml',b/'Manager.qml')
 put('Main.qml','''import QtQuick
import QtQuick.Controls
import Fk
Window{id:win;width:1100;height:620;visible:true;property var page:null;property var adapter:null
 Item{id:owner;property bool settingsReady:true}
 ResourcePackClient{id:client;owner:owner}
 Component{id:pageComponent;Manager{anchors.fill:parent}}
 Component{id:adapterComponent;ResourcePackDownload{}}
 function showPage(){page=pageComponent.createObject(win.contentItem);adapter=adapterComponent.createObject(page,{managerPage:page,client:client});}
 function hidePage(){page.destroy();page=null;adapter=null;}
 function request(action,pack){return client.request(action,pack);}
 function reply(ok,pack){
  delete Backend.files[client.bridge+"request.json"];delete Backend.files[client.bridge+"active.json"];
  Backend.files[client.bridge+"reply.json"]=JSON.stringify({id:client.requestId,operation:client.operation,packs:Backend.catalog.packs,ok:ok,pack:pack,error:ok?"":"cancelled"});client.poll();
 }
 function progress(){Backend.files[client.bridge+"progress.json"]=JSON.stringify({id:client.requestId,stage:"downloading",done:1048576,total:1311839017,part:1,parts:12});client.poll();}
 function staleReply(){Backend.files[client.bridge+"reply.json"]='{"id":"stale","ok":true,"pack":"奶杀动皮-v1"}';client.poll();}
 function addDirectory(){Backend.directories=["other-pack","奶杀动皮-v1"];}
 function disableMilk(){page.disablePack("奶杀动皮-v1");}
 function removeDirectory(){Backend.directories=["other-pack"];}
 function cancel(){client.cancel();}
 function pendingSettings(){owner.settingsReady=false;}
 function readySettings(){owner.settingsReady=true;}
 function state(){return JSON.stringify({busy:client.requestId!=="",id:client.requestId,enabled:Config.enabledResourcePacks,saves:Config.saves,status:client.status,cancelling:client.cancelling,pageEnabled:page?page.fullEnabledList:[],pageAvailable:page?page.fullAvailableList:[],offers:adapter?adapter.offers.map(p=>p.id):[],cancel:Backend.files[client.bridge+"cancel.json"],username:Config.username,password:Config.password});}
}''')
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.rootContext().setContextProperty('AppPath','file:///fixture');engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def pump(ms=80):loop=QEventLoop();QTimer.singleShot(ms,loop.quit);loop.exec()
 def call(name,*args,returns=False):
  arguments=[Q_ARG('QVariant',v) for v in args]
  result=QMetaObject.invokeMethod(win,name,Q_RETURN_ARG('QVariant'),*arguments) if returns else QMetaObject.invokeMethod(win,name,*arguments);pump();return result
 def state():return json.loads(QMetaObject.invokeMethod(win,'state',Q_RETURN_ARG('QVariant')))
 call('showPage');assert state()['busy'];call('reply',True,'');assert state()['offers']==['奶杀动皮-v1'],state()
 call('request','install','奶杀动皮-v1',returns=True);identifier=state()['id'];call('progress');assert 'MB' in state()['status'];call('staleReply');assert state()['id']==identifier
 win.grabWindow().save(str(a.output/'downloading.png'));call('hidePage');call('addDirectory');call('reply',True,'奶杀动皮-v1');assert state()['enabled']==['奶杀动皮-v1','other-pack'],state()
 call('showPage');call('reply',True,'');assert '奶杀动皮-v1' in state()['pageEnabled'] and not state()['offers'];win.grabWindow().save(str(a.output/'installed.png'))
 call('disableMilk');assert state()['enabled']==['other-pack'] and state()['pageAvailable']==['奶杀动皮-v1'],state()
 call('request','uninstall','奶杀动皮-v1',returns=True);call('removeDirectory');call('reply',True,'奶杀动皮-v1');assert state()['offers']==['奶杀动皮-v1'] and not state()['pageAvailable']
 call('request','install','奶杀动皮-v1',returns=True);call('cancel');s=state();assert s['cancelling'] and json.loads(s['cancel'])['id']==s['id'];call('reply',False,'奶杀动皮-v1');assert not state()['busy'] and state()['enabled']==['other-pack']
 call('request','install','奶杀动皮-v1',returns=True);call('pendingSettings');call('reply',True,'奶杀动皮-v1');assert state()['busy'] and state()['enabled']==['other-pack'];call('readySettings');assert not state()['busy'] and state()['enabled'][0]=='奶杀动皮-v1'
 assert state()['username']=='fixture-user' and state()['password']=='not-an-account'
 bad=[m for m in logs if any(s in m for s in ['ReferenceError','TypeError','Binding loop','Unable to assign','Cannot assign'])];assert not bad,bad
 result={'passed':True,'qt':__import__('PySide6').__version__,'stockManagerUsed':True,'downloadEnableAndReturnToAvailableAndDelete':True,'continuesAfterPageClosed':True,'waitsForSettingsBeforeEnabling':True,'cancelAndStaleReplyIsolation':True,'accountValuesPreserved':True,'deviceAcceptance':False};(a.output/'result.json').write_text(json.dumps(result,indent=2),'utf8');print(json.dumps(result))
