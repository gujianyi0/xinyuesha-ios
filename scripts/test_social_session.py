"""Validate saved-session reuse and 401 recovery against a local HTTP service."""
import argparse,json,os,threading,tempfile,time
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
os.environ.setdefault("QT_QPA_PLATFORM","offscreen")
from PySide6.QtCore import QUrl,QEventLoop,QTimer,QMetaObject,Q_RETURN_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
parser=argparse.ArgumentParser();parser.add_argument("--payload",type=Path,required=True);parser.add_argument("--work-dir",type=Path,required=True);a=parser.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
requests=[]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  body=json.loads(self.rfile.read(int(self.headers.get("Content-Length","0"))) or "{}");auth=self.headers.get("Authorization","");requests.append((self.path,auth))
  status=200;me={"id":"existing-friend-identity","name":"fixture","inviteMode":"original"}
  if self.path=="/v1/accounts/login":response={"token":"valid-session","me":me}
  elif auth!="Bearer valid-session":status=401;response={"error":"expired fixture session"}
  else:response={"me":me,"friends":[{"id":"retained-friend"}]}
  data=json.dumps(response).encode();self.send_response(status);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(data)));self.end_headers();self.wfile.write(data)
server=ThreadingHTTPServer(("127.0.0.1",0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();endpoint="http://127.0.0.1:"+str(server.server_port)
app=QGuiApplication([])
def pump(seconds):
 loop=QEventLoop();QTimer.singleShot(round(seconds*1000),loop.quit);loop.exec()
results={}
with tempfile.TemporaryDirectory(dir=a.work_dir) as tmp:
 base=Path(tmp);source=(a.payload/"card-counter/SocialClient.qml").read_text(encoding="utf8");source=source.replace('https://freekill-friends.pages.dev',endpoint);(base/"SocialClient.qml").write_text(source,encoding="utf8")
 (base/"SocialAuth.js").write_text('WorkerScript.onMessage=function(m){WorkerScript.sendMessage({generation:m.generation,key:"fixture-derived-key"});}',encoding="utf8")
 (base/"Main.qml").write_text('''import QtQml
QtObject {
 id:root;property int derivations:0;property string mode:"valid";property var writes:[]
 property var api:SocialClient {
  readProfile:function(key){return {token:root.mode==="expired"?"expired-session":"valid-session",enabled:root.mode!=="disabled",accountBound:true};}
  writeProfile:function(key,value){root.writes=root.writes.concat([JSON.stringify(value)]);}
  onDerivingChanged:if(deriving)root.derivations++
 }
 function setupValid(){setup("valid");}
 function setupExpired(){setup("expired");}
 function setupDisabled(){setup("disabled");}
 function setup(m){mode=m;api.bind({valid:true,server:"fixture:9527",gameId:1,name:"fixture",state:"lobby",roomId:0,roomName:""});api.setCredentials("fixture:9527","fixture-user","test-password-never-persist");}
 function repeatContext(){for(let i=0;i<10;i++){api.bind({valid:true,server:"fixture:9527",gameId:1,name:"fixture",state:i%2?"waiting":"lobby",roomId:0,roomName:""});api.setCredentials("fixture:9527","fixture-user","test-password-never-persist");}}
 function enable(){api.connectService();}
 function clear(){api.bind({valid:false,server:"",gameId:0,state:"offline"});}
 function state(){return JSON.stringify({derivations:derivations,connected:api.accountConnected,key:api.accountKey,token:api.token,pending:!!api.pendingCredentials,friends:api.friends.length,writes:writes});}
}''',encoding="utf8")
 for mode in ["Valid","Expired","Disabled"]:
  start=len(requests);engine=QQmlApplicationEngine();engine.load(QUrl.fromLocalFile(str(base/"Main.qml")));assert engine.rootObjects();root=engine.rootObjects()[0]
  def invoke(name):return QMetaObject.invokeMethod(root,name,Q_RETURN_ARG("QVariant"))
  def state():return json.loads(invoke("state"))
  invoke("setup"+mode);pump(.35)
  if mode=="Disabled":
   assert state()["derivations"]==0 and len(requests)==start,state();invoke("enable");pump(.35)
  first=state();assert first["connected"] and first["friends"]==1,first
  assert first["derivations"]==(1 if mode=="Expired" else 0),first
  invoke("repeatContext");pump(.25);after=state();assert after["derivations"]==first["derivations"],after
  assert all("test-password-never-persist" not in s and "fixture-derived-key" not in s for s in after["writes"]),"no credentials persisted"
  results[mode]={"derivations":after["derivations"],"identity_recovered":True,"requests":requests[start:]}
  invoke("clear");assert not state()["pending"] and state()["key"]=="",state();engine.deleteLater();pump(.05)
server.shutdown();print(json.dumps(results,indent=2));(a.work_dir/"result.json").write_text(json.dumps(results,indent=2),encoding="utf8")
