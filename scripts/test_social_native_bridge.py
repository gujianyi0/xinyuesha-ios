"""Exercise the real QML client through an asynchronous native Backend contract."""
import argparse,json,os,tempfile,time
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
from PySide6.QtCore import QObject,Signal,Slot,QTimer,QUrl,QEventLoop,QMetaObject,Q_RETURN_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
p=argparse.ArgumentParser();p.add_argument('--work-dir',type=Path,required=True);a=p.parse_args();a.work_dir.mkdir(parents=True,exist_ok=True)
R=Path(__file__).resolve().parents[1];app=QGuiApplication([])
class Backend(QObject):
 socialRequestFinished=Signal(int,int,str,int,str)
 def __init__(self):super().__init__();self.sequence=0;self.mode='ok';self.requests=[];self.cancelled=[];self.fail_mutations=False
 @Slot(str,str,str,str,result=int)
 def startSocialRequest(self,method,url,bearer,body):
  self.sequence+=1;id=self.sequence;data=json.loads(body or '{}');self.requests.append((id,method,url,bearer,data));mode=self.mode
  def done():
   # Deliver even a cancelled callback to check the QML generation guard too.
   if mode=='hold':self.socialRequestFinished.emit(id,0,'',-1009,'NSURLErrorDomain / -1009');return
   if mode=='tls' or (mode=='fallback' and 'xinyuesha-friends-api' not in url):self.socialRequestFinished.emit(id,0,'',-1202,'服务器证书不受信任（NSURLErrorDomain / -1202）');return
   if mode=='bic':self.socialRequestFinished.emit(id,403,'error code: 1010',0,'');return
   if self.fail_mutations and url.endswith('/v1/friends/request'):self.socialRequestFinished.emit(id,0,'',-1001,'请求超时（NSURLErrorDomain / -1001）');return
   result={'me':{'id':'same-identity','name':'fixture'},'friends':[{'id':'retained-friend'}]}
   if url.endswith('/v1/accounts/login'):assert data['key']=='fixture-key';result['token']='valid'
   else:assert bearer=='valid'
   self.socialRequestFinished.emit(id,200,json.dumps(result),0,'')
  QTimer.singleShot(150 if mode=='hold' else 5,done);return id
 @Slot(int)
 def cancelSocialRequest(self,id):self.cancelled.append(id)
backend=Backend();results={}
def pump(seconds=.15):
 loop=QEventLoop();QTimer.singleShot(round(seconds*1000),loop.quit);loop.exec()
with tempfile.TemporaryDirectory(dir=a.work_dir) as temp:
 B=Path(temp);(B/'SocialClient.qml').write_bytes((R/'runtime/card-counter/SocialClient.qml').read_bytes())
 (B/'SocialAuth.js').write_text('WorkerScript.onMessage=function(m){WorkerScript.sendMessage({generation:m.generation,key:"fixture-key"});}',encoding='utf-8')
 (B/'Main.qml').write_text('''import QtQml
QtObject {id:root;property bool fresh:false;property var saved:({})
 property var api:SocialClient {readProfile:function(k){return {token:root.fresh?"":"valid",accountBound:!root.fresh};}writeProfile:function(k,v){root.saved=v;}}
 function setup(){api.bind({valid:true,server:"fixture:9527",gameId:1,name:"fixture",state:"lobby",roomId:0});api.setCredentials("fixture:9527","fixture","fixture-password");}
 function clear(){api.clearSession();}
 function add(){api.addFriend("123456789ABC");}
 function state(){return JSON.stringify({native:api.nativeTransportAvailable,id:api.me.id||"",token:api.token,busy:api.busy,calls:api.calls.length,error:api.error,backup:api.useBackupTransport,endpoint:api.endpoint,saved:saved});}
}''',encoding='utf-8')
 def create(mode,fresh=False):
  backend.mode=mode;backend.requests=[];backend.cancelled=[];backend.fail_mutations=False
  e=QQmlApplicationEngine();e.warnings.connect(lambda errors:print('\n'.join(x.toString() for x in errors)));e.rootContext().setContextProperty('Backend',backend);e.load(QUrl.fromLocalFile(str(B/'Main.qml')));assert e.rootObjects();r=e.rootObjects()[0];r.setProperty('fresh',fresh);return e,r
 def invoke(r,n):return QMetaObject.invokeMethod(r,n,Q_RETURN_ARG('QVariant'))
 def state(r):return json.loads(invoke(r,'state'))
 def close(e,r):invoke(r,'clear');e.deleteLater();pump(.02)
 e,r=create('fallback');invoke(r,'setup');pump();s=state(r)
 assert s['native'] and s['id']=='same-identity' and s['backup'] and s['endpoint']=='https://freekill-friends.pages.dev',s
 assert len(backend.requests)==2 and all(x[1]=='POST' and x[3]=='valid' for x in backend.requests)
 results['native_fallback_preserves_identity']=True;close(e,r)
 e,r=create('ok',True);invoke(r,'setup');pump(.3);s=state(r);assert s['id']=='same-identity' and s['token']=='valid',s
 assert backend.requests[0][2].endswith('/v1/accounts/login') and backend.requests[0][3]==''
 results['native_login_and_sync']=True;close(e,r)
 e,r=create('tls');invoke(r,'setup');pump();s=state(r);assert '-1202' in s['error'] and not s['busy'] and s['calls']==0 and len(backend.requests)==2,s
 results['system_failure_code']=s['error'];close(e,r)
 e,r=create('bic');invoke(r,'setup');pump();s=state(r);assert '403 / 1010' in s['error'] and len(backend.requests)==1,s
 results['http_error_not_replayed']=True;close(e,r)
 e,r=create('hold');invoke(r,'setup');pump(.03);invoke(r,'clear');pump(.3);s=state(r)
 assert s['calls']==0 and not s['token'] and len(backend.requests)==1 and backend.cancelled,s
 results['logout_cancels_and_ignores_late_callback']=True;e.deleteLater();pump(.02)
 e,r=create('ok');invoke(r,'setup');pump();backend.fail_mutations=True;start=len(backend.requests);invoke(r,'add');pump();s=state(r)
 assert len(backend.requests)==start+1 and '-1001' in s['error'] and '超时' in s['error'],s
 results['native_mutation_not_replayed']=True;close(e,r)
print(json.dumps(results,ensure_ascii=False,indent=2));(a.work_dir/'result.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
