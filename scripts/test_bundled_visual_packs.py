"""Exercise first-run pack activation and preservation of user choices in QML."""
import argparse, json, os, shutil, tempfile
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
from PySide6.QtCore import QUrl, QMetaObject, Q_RETURN_ARG, Q_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);a=p.parse_args()
app=QGuiApplication([]);logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m))
with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary)
    def put(name,text):
        f=root/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text,encoding='utf8')
    put('Fk/qmldir','module Fk\n'+''.join('singleton '+n+' 1.0 '+n+'.qml\n' for n in ['Cpp','Backend','Config','Mediator']))
    put('Fk/Cpp.qml','pragma Singleton\nimport QtQuick\nQtObject{property string os:"iOS"}')
    put('Fk/Mediator.qml','pragma Singleton\nimport QtQuick\nQtObject{signal commandGot(var sender,string command,var data)}')
    put('Fk/Config.qml','''pragma Singleton
import QtQuick
QtObject{property list<string> enabledResourcePacks:["user-pack"];property int saves:0
 function saveConf(){saves++;}}''')
    put('Fk/Backend.qml','''pragma Singleton
import QtQuick
QtObject{property string marker:"{}";property bool failWrite:false;property bool complete:true
 property var catalog:({schema:1,bundleId:"one",packs:[{id:"A",requiredFile:"assets/a/manifest.json"},{id:"B",requiredFile:"assets/b/manifest.json"}]})
 function readFileFromAssets(path){return path==="function-settings.json"?"{}":marker;}
 function readJsonObjectFromFile(path){return catalog;}
 function exists(path){return complete;}
 function writeFileToAssets(path,text){if(failWrite)return false;marker=text;return true;}}
''')
    shutil.copyfile(a.payload/'card-counter/FeedbackFeatures.qml',root/'FeedbackFeatures.qml')
    put('Main.qml','''import QtQuick
import Fk
Item{
 Item{id:owner;property bool settingsReady:false;property var currentScene:null}
 FeedbackFeatures{id:features;owner:owner}
 function ready(){owner.settingsReady=true;}
 function run(){features.ensureBundledPacks();}
 function disableB(){Config.enabledResourcePacks=["user-pack","A"];}
 function newRevision(){Backend.catalog={schema:1,bundleId:"two",packs:[{id:"A",requiredFile:"a"},{id:"B",requiredFile:"b"},{id:"C",requiredFile:"c"}]};}
 function missing(){Backend.complete=false;}
 function complete(){Backend.complete=true;}
 function malformed(){Backend.marker="invalid";}
 function reset(){Backend.marker="{}";Config.enabledResourcePacks=["user-pack"];}
 function fail(){Backend.failWrite=true;}
 function android(){Cpp.os="Android";}
 function state(){return JSON.stringify({enabled:Config.enabledResourcePacks,marker:Backend.marker,saves:Config.saves,error:features.settingsError});}
}''')
    engine=QQmlApplicationEngine();engine.addImportPath(str(root));engine.load(QUrl.fromLocalFile(str(root/'Main.qml')))
    assert engine.rootObjects(),logs
    item=engine.rootObjects()[0]
    def call(name):QMetaObject.invokeMethod(item,name)
    def state():return json.loads(QMetaObject.invokeMethod(item,'state',Q_RETURN_ARG('QVariant')))
    app.processEvents();assert state()['enabled']==['user-pack']
    call('ready');assert state()['enabled']==['user-pack','A','B'] and state()['saves']==1,state()
    call('disableB');call('run');assert state()['enabled']==['user-pack','A'] and state()['saves']==1,state()
    call('newRevision');call('missing');call('run');assert state()['enabled']==['user-pack','A'] and json.loads(state()['marker'])['bundleId']=='one',state()
    call('complete');call('run');assert state()['enabled']==['user-pack','A','C'],state()
    call('malformed');before=state();call('run');assert state()['enabled']==before['enabled'] and state()['marker']=='invalid',state()
    call('reset');call('fail');call('run');assert state()['marker']=='{}' and state()['error'],state()
    call('reset');call('android');call('run');assert state()['enabled']==['user-pack'],state()
    errors=[m for m in logs if any(s in m for s in ['TypeError','ReferenceError','Cannot assign','Unable to assign'])];assert not errors,errors
    print(json.dumps({'passed':True,'payload':str(a.payload),'qt':__import__('PySide6').__version__,'firstRunEnabled':True,'userPacksAndDisabledChoicesPreserved':True,'incompleteAndCorruptStateRetained':True,'androidInstallerUnaffected':True,'deviceAcceptance':False}))
