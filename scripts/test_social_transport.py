# SPDX-License-Identifier: GPL-3.0-or-later
"""Real QML XHR failover; never replay friend mutations after an unknown outcome."""
import argparse,json,os,socket,tempfile,threading,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtCore import QUrl,QMetaObject,Q_RETURN_ARG,QEventLoop,QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
p=argparse.ArgumentParser();p.add_argument('--payload',type=Path,required=True);p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
class Service(ThreadingHTTPServer):
 daemon_threads=True
 def __init__(self):super().__init__(('127.0.0.1',0),Handler);self.mode='ok';self.calls=[];self.agents=[];self.friend_effects=0
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  body=self.rfile.read(int(self.headers.get('Content-Length',0)));self.server.calls.append(self.path)
  self.server.agents.append((self.headers.get('User-Agent'),self.headers.get('Accept')))
  if self.path=='/v1/friends/request':self.server.friend_effects+=1
  mode=self.server.mode
  if mode=='drop':self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
  if mode=='timeout':time.sleep(2);return
  if mode in ['bic','html','unavailable']:
   blob={'bic':b'error code: 1010\n','html':b'<html>not an API response</html>','unavailable':b'upstream unavailable'}[mode]
   self.send_response({'bic':403,'html':200,'unavailable':503}[mode]);self.send_header('Content-Length',str(len(blob)));self.end_headers();self.wfile.write(blob);return
  me={'id':'same-cloud-identity','name':'fixture','inviteMode':'original'}
  status=200
  if self.path=='/v1/accounts/login':data={'token':'valid','me':me}
  elif self.headers.get('Authorization')!='Bearer valid':status=401;data={'error':'expired'}
  else:data={'me':me,'friends':[{'id':'retained-friend'}]}
  blob=json.dumps(data).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(blob)));self.end_headers()
  try:self.wfile.write(blob)
  except (BrokenPipeError,ConnectionResetError):pass
primary=Service();backup=Service()
for s in [primary,backup]:threading.Thread(target=s.serve_forever,daemon=True).start()
origin=lambda s:'http://127.0.0.1:'+str(s.server_port)
app=QGuiApplication([])
def pump(seconds):
 loop=QEventLoop();QTimer.singleShot(round(seconds*1000),loop.quit);loop.exec()
results={}
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 B=Path(temp)
 source=(a.payload/'card-counter/SocialClient.qml').read_text(encoding='utf-8').replace('https://freekill-friends.pages.dev',origin(primary)).replace('https://xinyuesha-friends-api.pages.dev',origin(backup)).replace('Date.now() + 10000','Date.now() + 120').replace('Date.now() + (useNative ? 16000 : 10000)','Date.now() + 120')
 (B/'SocialClient.qml').write_text(source,encoding='utf-8')
 (B/'SocialAuth.js').write_text('WorkerScript.onMessage=function(m){WorkerScript.sendMessage({generation:m.generation,key:"test-key"});}',encoding='utf-8')
 (B/'Main.qml').write_text('''import QtQml
QtObject {
 id:root;property string mode:"saved";property var saved:({});property int derives:0
 property var api:SocialClient {
  readProfile:function(k){return {endpoint:root.mode==="savedApiPath"?root.api.fallbackEndpoint+"/v1/state/":"",token:root.mode==="fresh"?"":root.mode==="expired"?"expired":"valid",enabled:true,accountBound:root.mode!=="fresh"};}
  writeProfile:function(k,v){root.saved=v;}
  onDerivingChanged:if(deriving)root.derives++
 }
 function setup(){api.bind({valid:true,server:"fixture:9527",gameId:1,name:"fixture",state:"lobby",roomId:0});api.setCredentials("fixture:9527","fixture","test-password");}
 function add(){api.useBackupTransport=false;api.addFriend("123456789ABC");}
 function alias(){return api.configure(api.fallbackEndpoint);}
 function apiAlias(){return api.configure(api.fallbackEndpoint+"/v1/state/");}
 function invalidAlias(){return api.configure(api.fallbackEndpoint+"/wrong-path");}
 function state(){return JSON.stringify({id:api.me.id||"",friends:api.friends.length,token:api.token,backup:api.useBackupTransport,busy:api.busy,calls:api.calls.length,error:api.error,scope:api.profileKey,endpoint:api.endpoint,saved:saved,derives:derives});}
 function clear(){api.clearSession();}
}''',encoding='utf-8')
 def create(mode='saved'):
  e=QQmlApplicationEngine();e.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert e.rootObjects();r=e.rootObjects()[0];r.setProperty('mode',mode);return e,r
 def invoke(r,n):return QMetaObject.invokeMethod(r,n,Q_RETURN_ARG('QVariant'))
 def state(r):return json.loads(invoke(r,'state'))
 primary.mode='drop';backup.mode='ok';e,r=create();invoke(r,'setup');pump(.5);s=state(r)
 assert s['id']=='same-cloud-identity' and s['friends']==1 and s['backup'] and s['derives']==0,s
 assert s['saved']['endpoint']==origin(primary),'fallback must not change logical identity endpoint'
 assert invoke(r,'alias') and state(r)['token']=='valid' and state(r)['scope']==s['scope'],'explicit alias preserves account'
 results['drop_to_backup']=s
 if a.payload.name=='runtime':
  assert invoke(r,'apiAlias') and state(r)['endpoint']==origin(primary) and state(r)['token']=='valid'
  assert state(r)['derives']==0 and state(r)['id']==s['id'],'test URL normalization must preserve session and identity'
  assert invoke(r,'invalidAlias') is False and state(r)['token']=='valid','reject unknown API paths before clearing session'
  assert invoke(r,'alias');results['api_path_configure_preserves_identity']=True
 primary.mode='timeout';start=len(backup.calls);invoke(r,'add');pump(.7)
 assert primary.friend_effects==1 and '/v1/friends/request' not in backup.calls[start:],'do not replay friend requests'
 assert not state(r)['busy'] and '超时' in state(r)['error'],state(r)
 results['mutation_not_replayed']=True;invoke(r,'clear');e.deleteLater();pump(.05)
 primary.mode='timeout';e,r=create('fresh');invoke(r,'setup');pump(.8);s=state(r)
 assert s['id']=='same-cloud-identity' and s['backup'] and s['derives']==1 and s['calls']==0,s
 results['login_timeout_recovered']=s;invoke(r,'clear');e.deleteLater();pump(.05)
 primary.mode='drop';backup.mode='ok';e,r=create('expired');invoke(r,'setup');pump(.6);s=state(r)
 assert s['id']=='same-cloud-identity' and s['derives']==1 and s['backup'],s
 results['expired_backup_authentication']=True;invoke(r,'clear');e.deleteLater();pump(.05)
 primary.mode='drop';backup.mode='drop';e,r=create();invoke(r,'setup');pump(.5);s=state(r)
 assert s['calls']==0 and not s['busy'] and '主、备用' in s['error'],s
 results['both_unreachable']=s['error'];invoke(r,'clear');e.deleteLater();pump(.05)
 primary.mode='timeout';backup.mode='ok';e,r=create();start=len(backup.calls);invoke(r,'setup');invoke(r,'clear');pump(.7)
 assert len(backup.calls)==start and state(r)['calls']==0,'logout abort must not launch fallback with stale credentials'
 results['logout_cancels_without_fallback']=True;e.deleteLater();pump(.05)
 if a.payload.name=='runtime':
  for mode,expected in [('bic','403 / 1010'),('html','格式异常'),('unavailable','HTTP 503')]:
   primary.mode=mode;backup.mode='ok';start=len(backup.calls);e,r=create();invoke(r,'setup');pump(.3);s=state(r)
   assert expected in s['error'] and not s['busy'] and s['calls']==0,s
   assert len(backup.calls)==start,'HTTP response errors must not be replayed'
   assert primary.agents[-1]==('Xinyuesha-Test/0.5.25','application/json')
   assert s['token']=='valid','an unexpected response must not erase saved identity'
   results[mode+'_diagnostic']=s['error'];invoke(r,'clear');e.deleteLater();pump(.05)
  primary.mode='ok';backup.mode='ok';start=len(primary.calls);e,r=create('savedApiPath');invoke(r,'setup');pump(.4);s=state(r)
  assert s['id']=='same-cloud-identity' and s['backup'] and s['derives']==0 and s['endpoint']==origin(primary),s
  assert len(primary.calls)==start,'a stored backup test URL must restore the backup transport directly'
  results['saved_api_path_repaired']=True;invoke(r,'clear');e.deleteLater();pump(.05)
for s in [primary,backup]:s.shutdown()
print(json.dumps(results,ensure_ascii=False,indent=2));(a.work_dir/'result.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
