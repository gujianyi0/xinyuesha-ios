"""Actual QML/XHR merging with isolated HTTP failures and fixture favorites."""
import argparse,json,os,shutil,tempfile,http.server,threading,time
from pathlib import Path
os.environ.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,QEventLoop,QTimer,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  data=json.dumps({'not':'a list'} if self.path=='/bad' else [{'addr':'new.example.test','port':9527,'name':'New server','password':'must-not-cache'},{'addr':'file:///not-a-server','port':9527},{'addr':'invalid-port.test','port':65536}]).encode()
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
logs=[];qInstallMessageHandler(lambda k,c,m:logs.append(m));app=QGuiApplication([])
with tempfile.TemporaryDirectory(dir=a.output) as temp:
 b=Path(temp)
 def put(name,value):
  path=b/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value,'utf8')
 put('Fk/qmldir','module Fk\nsingleton Config 1.0 Config.qml\nsingleton Backend 1.0 Backend.qml\n')
 put('Fk/Config.qml','pragma Singleton\nimport QtQuick\nQtObject{property int saves:0;function saveConf(){saves++;}}')
 seed=json.loads((a.payload/'card-counter/public-servers.json').read_text('utf8'))
 put('Fk/Backend.qml','pragma Singleton\nimport QtQuick\nQtObject{function readJsonObjectFromFile(path){return '+json.dumps(seed,ensure_ascii=False)+';}}')
 shutil.copyfile(a.payload/'card-counter/PublicServerList.qml',b/'PublicServerList.qml')
 put('Main.qml','''import QtQuick
import Fk
Window{id:win;width:400;height:200;visible:true
 Item{id:page;property var rows:[];property string cached:"";property bool favoritesLoaded:false
  function appendServers(list){const next=Array.from(rows);for(const row of list)if(!next.some(s=>s.addr===row.addr&&s.port===row.port))next.push(row);rows=next;}
  function loadConfig(){if(!favoritesLoaded){favoritesLoaded=true;appendServers([{addr:"private.example.test",port:9527,name:"Favorite",username:"fixture-user",password:"fixture-only"}]);}}
  function writeCache(key,value){if(key==="json")cached=value;}
 }
 PublicServerList{id:bridge;page:page;urls:["http://127.0.0.1:PORT/bad","http://127.0.0.1:PORT/good"]}
 function snapshot(){return JSON.stringify({rows:page.rows,cached:page.cached,saves:Config.saves});}
}'''.replace('PORT',str(server.server_port)))
 engine=QQmlApplicationEngine();engine.addImportPath(str(b));engine.load(QUrl.fromLocalFile(str(b/'Main.qml')));assert engine.rootObjects(),logs;win=engine.rootObjects()[0]
 def state():return json.loads(QMetaObject.invokeMethod(win,'snapshot',Q_RETURN_ARG('QVariant')))
 end=time.monotonic()+5
 while not state()['saves'] and time.monotonic()<end:
  loop=QEventLoop();QTimer.singleShot(20,loop.quit);loop.exec()
 s=state();assert s['saves']==1,s
 assert len(s['rows'])==len(seed['servers'])+2,s
 favorite=s['rows'][0];assert favorite['password']=='fixture-only' and favorite['username']=='fixture-user',s
 assert any(row['addr']=='139.196.92.71' for row in s['rows']),s
 cache=json.loads(s['cached']);assert len(cache)==1 and 'password' not in cache[0] and cache[0]['addr']=='new.example.test',cache
 errors=[m for m in logs if any(k in m for k in ['TypeError','ReferenceError','Cannot assign','Unable to assign'])];assert not errors,errors
 report=dict(passed=True,bundledServers=len(seed['servers']),favoritesAndCredentialsRetained=True,invalidFirstEndpointFallsBack=True,invalidRowsRejected=True,publicCacheExcludesCredentials=True,actualQmlXhr=True,nativeUiIncluded=False)
 (a.output/'result.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report));win.close()
server.shutdown()
