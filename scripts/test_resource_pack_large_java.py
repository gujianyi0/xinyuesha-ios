"""Stream the real milk pack through the production Java installer with 48 MiB heap.

Uses local HTTP, disposable app state, and an explicitly supplied local source map.
No device access or public writes.
"""
import argparse, hashlib, http.server, json, os, shutil, subprocess, tempfile, threading
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1];catalog=json.loads((root/'runtime/card-counter/resource-catalog.json').read_text('utf8'));milk=next(p for p in catalog['packs'] if p['id']=='奶杀动皮-v1');fixture=dict(catalog,packs=[milk]);sources={p['archive']:Path(p['source']) for p in json.loads(a.sources.read_text('utf8'))};requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        if self.path=='/catalog.json':
            body=json.dumps(fixture,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
        name=self.path.rsplit('/',1)[-1]
        if name not in sources:self.send_error(404);return
        file=sources[name];self.send_response(200);self.send_header('Content-Length',str(file.stat().st_size));self.end_headers();requests.append(name)
        with file.open('rb') as stream:shutil.copyfileobj(stream,self.wfile,65536)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();origin=f'http://127.0.0.1:{server.server_port}'
try:
    with tempfile.TemporaryDirectory(prefix='java-large-',dir=a.output) as temp:
        work=Path(temp);app=work/'app';(app/'assets/resource-pack-download').mkdir(parents=True)
        config=b'{"username":"fixture","password":"not-an-account","enabledResourcePacks":[]}'
        (app/'freekill.client.config.json').write_bytes(config);(app/'assets/resource-pack-download/request.json').write_text('{"id":"35002","operation":"install","pack":"奶杀动皮-v1"}','utf8')
        jar=root/'work/embedded-v1-20261121/json-20240303.jar';jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Android/openjdk/jdk-21.0.8'))/'bin'
        # The same already-reviewed standalone entry point from the protocol test.
        harness=root/'work/resource-download-20261126/protocol-tests-winhttp/java/ResourceDownloadHarness.java';assert harness.is_file()
        classes=work/'classes';classes.mkdir();subprocess.run([str(jdk/'javac.exe'),'-encoding','UTF-8','-cp',str(jar),'-d',str(classes),str(root/'android/java/org/notify/FreeKill/ResourcePackInstaller.java'),str(harness)],check=True)
        result=subprocess.run([str(jdk/'java.exe'),'-Xmx48m','-cp',str(classes)+os.pathsep+str(jar),'org.notify.FreeKill.ResourceDownloadHarness',str(app),origin],capture_output=True,timeout=600,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0));assert result.returncode==0,result.stderr
        reply=json.loads(result.stdout.decode('utf8'));assert reply['ok'],reply
        destination=app/'resource_pak/奶杀动皮-v1';files=[f for f in destination.rglob('*') if f.is_file()];assert len(files)==milk['fileCount'] and sum(f.stat().st_size for f in files)==milk['expandedBytes'];assert len(requests)==12;assert (app/'freekill.client.config.json').read_bytes()==config
        assert not list((app/'assets/resource-pack-download/cache').glob('*.zip'))
        skins=json.loads((destination/'packages/freekill-core/image/xinyuesha-naisha/catalog.json').read_text('utf8'));assert len(skins['skins'])==244
        report={'passed':True,'productionJavaInstaller':True,'javaMaxHeapMiB':48,'realCompressedBytes':milk['bytes'],'realExpandedBytes':milk['expandedBytes'],'parts':len(requests),'files':len(files),'skins':244,'configUnchanged':True,'successfulCacheRemoved':True,'network':'loopback HTTP serving exact pinned production archives','deviceAcceptance':False}
        (a.output/'result.json').write_text(json.dumps(report,indent=2)+'\n','utf8');print(json.dumps(report))
finally:server.shutdown()
