"""Real HTTP, resume and transactional extraction on the shipped Qt/Java code.

Only loopback fixture servers and disposable app directories are used.
"""
import argparse,hashlib,http.server,io,json,os,shutil,socket,subprocess,tempfile,threading,time,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--qt',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--skip-java',action='store_true');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1];objects={};requests=[];mode={'drop':None,'bad':None,'slow':False};catalog={}
def digest(data):return hashlib.sha256(data).hexdigest()
def pack(name,entries):
    buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w',zipfile.ZIP_STORED) as z:
        for path,data in entries:z.writestr(path,data)
    data=buffer.getvalue();objects[name]=data
    return {'archive':name,'bytes':len(data),'sha256':digest(data),'expandedBytes':sum(len(d) for _,d in entries),'fileCount':len(entries)}
def row(parts,identity='测试资源'):
    return {'id':identity,'title':identity,'version':'fixture','bytes':sum(p['bytes'] for p in parts),'expandedBytes':sum(p['expandedBytes'] for p in parts),'fileCount':sum(p['fileCount'] for p in parts),'parts':parts}
first=pack('part-a.zip',[('icon.png',b'fixture'),('packages/core/image/a.png',os.urandom(500000))]);second=pack('part-b.zip',[('packages/core/image/中文.json',os.urandom(900000))]);good=row([first,second]);catalog.update(schema=2,packs=[good])
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        if self.path=='/catalog.json':data=json.dumps(catalog,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data);return
        name=self.path.rsplit('/',1)[-1];data=objects.get(name)
        if data is None:self.send_error(404);return
        header=self.headers.get('Range');offset=int(header[6:-1]) if header and header.startswith('bytes=') else 0;requests.append((name,offset))
        self.send_response(206 if offset else 200);self.send_header('Content-Length',str(len(data)-offset))
        if offset:self.send_header('Content-Range',f'bytes {offset}-{len(data)-1}/{len(data)}')
        self.end_headers();data=(bytes([data[0]^1])+data[1:]) if mode['bad']==name else data
        drop=mode['drop']==name
        if drop:mode['drop']=None;data=data[:len(data)//2]
        try:
            for pos in range(offset,len(data),8192):self.wfile.write(data[pos:pos+8192]);self.wfile.flush();time.sleep(.012 if mode['slow'] else 0)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
        if drop:
            try:self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            self.connection.close()
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
env=dict(os.environ)
if a.qt:env['PATH']=str(a.qt/'bin')+os.pathsep+env['PATH']
env.pop('HTTP_PROXY',None);env.pop('HTTPS_PROXY',None)
commands={'Qt':[str(a.native.resolve())]}
work=a.output/'java';work.mkdir(exist_ok=True)
if not a.skip_java:
    jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Android/openjdk/jdk-21.0.8'))/'bin';jar=root/'work/embedded-v1-20261121/json-20240303.jar';assert jar.is_file()
    harness=work/'ResourceDownloadHarness.java';harness.write_text('''package org.notify.FreeKill;
import org.json.*;import java.nio.file.*;import java.net.*;import java.io.*;import java.nio.charset.StandardCharsets;
public class ResourceDownloadHarness {
 public static void main(String[] args)throws Exception {
  Path root=Paths.get(args[0]);JSONObject request=new JSONObject(new String(Files.readAllBytes(root.resolve("assets/resource-pack-download/request.json")),StandardCharsets.UTF_8));
  JSONObject reply=new JSONObject().put("id",request.getString("id")).put("ok",false);
  try {
   HttpURLConnection connection=(HttpURLConnection)new URL(args[1]+"/catalog.json").openConnection();ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=connection.getInputStream()){byte[] b=new byte[8192];for(int n;(n=in.read(b))!=-1;)out.write(b,0,n);}finally{connection.disconnect();}
   JSONArray packs=ResourcePackInstaller.validate(new JSONObject(new String(out.toByteArray(),StandardCharsets.UTF_8)));JSONObject pack=packs.getJSONObject(0);
   ResourcePackInstaller installer=new ResourcePackInstaller(root,args[1],request.getString("id"),(stage,done,total,part,parts)->{});installer.install(pack,null);reply.put("ok",true);
  }catch(Exception error){reply.put("error",error.getMessage());}
  System.out.write(reply.toString().getBytes(StandardCharsets.UTF_8));
 }
}''','utf8');classes=work/'classes';classes.mkdir(exist_ok=True)
    subprocess.run([str(jdk/'javac.exe'),'-encoding','UTF-8','-cp',str(jar),'-d',str(classes),str(root/'android/java/org/notify/FreeKill/ResourcePackInstaller.java'),str(harness)],check=True)
    commands['Java']=[str(jdk/'java.exe'),'-Xmx48m','-cp',str(classes)+os.pathsep+str(jar),'org.notify.FreeKill.ResourceDownloadHarness']
results=[]
try:
 with tempfile.TemporaryDirectory(prefix='resource-network-',dir=a.output) as temp:
    for platform,command in commands.items():
        base=Path(temp)/platform;base.mkdir();bridge=base/'assets/resource-pack-download';bridge.mkdir(parents=True);private=b'{"username":"fixture","password":"not-an-account","future":7,"enabledResourcePacks":[]}';(base/'freekill.client.config.json').write_bytes(private)
        sequence=[0]
        def run(expect,identity='测试资源',cancel=False):
            sequence[0]+=1;request={'id':str(sequence[0]),'operation':'install','pack':identity};(bridge/'request.json').write_text(json.dumps(request,ensure_ascii=False),'utf8');(bridge/'reply.json').unlink(missing_ok=True)
            proc=subprocess.Popen(command+[str(base.resolve()),origin],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            if cancel:
                deadline=time.monotonic()+10
                while time.monotonic()<deadline and not list((bridge/'cache').glob('*.partial')):time.sleep(.02)
                time.sleep(.08);(bridge/'cancel.json').write_text(json.dumps({'id':request['id']}),'utf8')
            out,err=proc.communicate(timeout=40);assert proc.returncode==0,(platform,out,err)
            value=json.loads(out.decode('utf8'));assert value['ok']==expect,(platform,value,err.decode(errors='replace'));assert (base/'freekill.client.config.json').read_bytes()==private,'Installer wrote account settings'
            return value
        # Fail halfway through part B, with part A already validated/extracted.
        mode['drop']='part-b.zip';catalog['packs']=[good];run(False);assert not (base/'resource_pak/测试资源').exists();assert list((bridge/'cache').glob('*.partial'))
        before=len([r for r in requests if r[0]=='part-a.zip']);run(True);assert before==len([r for r in requests if r[0]=='part-a.zip']),'Completed part downloaded again';assert any(name=='part-b.zip' and offset>0 for name,offset in requests),'Range resume was not used'
        for part in [first,second]:
            with zipfile.ZipFile(io.BytesIO(objects[part['archive']])) as z:
                for info in z.infolist():assert (base/'resource_pak/测试资源'/info.filename).read_bytes()==z.read(info)
        assert not list((bridge/'cache').glob('*.zip')),'Successful download cache not freed'
        cases=[('traversal','packages/../escape.png'),('code','packages/core/player.qml'),('absolute','/packages/escape.png')]
        for title,path in cases:
            part=pack(title+'.zip',[(path,b'bad')]);catalog['packs']=[row([part],title)];run(False,title);assert not (base/'resource_pak'/title).exists()
        part=pack('corrupt.zip',[('packages/core/a.png',b'original')]);catalog['packs']=[row([part],'corrupt')];mode['bad']='corrupt.zip';run(False,'corrupt');mode['bad']=None;assert not (base/'resource_pak/corrupt').exists();run(True,'corrupt')
        cancelpart=pack('cancel.zip',[('packages/core/cancel.png',os.urandom(1200000))]);catalog['packs']=[row([cancelpart],'cancel')];mode['slow']=True;run(False,'cancel',cancel=True);mode['slow']=False;assert not (base/'resource_pak/cancel').exists();run(True,'cancel')
        results.append({'platform':platform,'passed':True,'httpResume':True,'completedPartReused':True,'partialInstallHidden':True,'corruptTraversalCodeAbsoluteRejected':True,'cancelAndRetry':True,'accountConfigUnchanged':True})
finally:server.shutdown()
report={'passed':True,'tests':results,'deviceAccessed':False,'network':'loopback HTTP with forced disconnect, corruption and cancellation'};(a.output/'result.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report))
