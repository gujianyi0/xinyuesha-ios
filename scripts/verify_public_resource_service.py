"""Read every pinned CDN object and exercise the real native installer.

Public read-only requests; temporary synthetic app state; no phone/feedback writes.
"""
import argparse,concurrent.futures,hashlib,json,os,subprocess,tempfile,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--pack',help='Verify only the changed pack, retaining immutable prior-object evidence');p.add_argument('--origin',default='https://gujianyi-xinyuesha-resources.pages.dev');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1];catalogPath=root/'runtime/card-counter/resource-catalog.json';catalog=json.loads(catalogPath.read_text('utf8'));parts=[p for pack in catalog['packs'] for p in pack['parts']]
if a.pack:parts=[part for pack in catalog['packs'] if pack['id']==a.pack for part in pack['parts']];assert parts,'Pack not found'
def fetch(part):
    request=urllib.request.Request(a.origin+'/download/'+part['archive'],headers={'User-Agent':'FreeKill Resource Download','Accept-Encoding':'identity'})
    digest=hashlib.sha256();total=0;first=b'';last=b''
    with urllib.request.urlopen(request,timeout=45) as response:
        assert response.status==200
        while block:=response.read(256*1024):
            if not first:first=block[:4]
            last=(last+block)[-4:];total+=len(block);assert total<=part['bytes'];digest.update(block)
    assert total==part['bytes'] and digest.hexdigest()==part['sha256'],part['archive']
    for value,expected in [('bytes=0-3',first),('bytes=-4',last)]:
        req=urllib.request.Request(a.origin+'/download/'+part['archive'],headers={'User-Agent':'FreeKill Resource Download','Range':value})
        with urllib.request.urlopen(req,timeout=30) as response:assert response.status==206 and response.read()==expected
    return {'archive':part['archive'],'bytes':total,'sha256':digest.hexdigest(),'httpBodyVerified':True,'prefixSuffixRangesVerified':True}
rows=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for future in concurrent.futures.as_completed([pool.submit(fetch,p) for p in parts]):
        rows.append(future.result());(a.output/'http-objects.json').write_text(json.dumps(rows,indent=2),'utf8');print(json.dumps({'verified':len(rows),'total':len(parts)}),flush=True)
with tempfile.TemporaryDirectory(prefix='public-resource-native-') as temp:
    app=Path(temp);bridge=app/'assets/resource-pack-download';bridge.mkdir(parents=True);(app/'card-counter').mkdir();(app/'card-counter/resource-catalog.json').write_bytes(catalogPath.read_bytes());private=b'{"fixture":true,"username":"not-a-user","enabledResourcePacks":[]}';(app/'freekill.client.config.json').write_bytes(private)
    identity=a.pack or '奶杀动皮-v1'
    (bridge/'request.json').write_text(json.dumps({'id':'35001','operation':'install','pack':identity},ensure_ascii=False),'utf8')
    env=dict(os.environ,FK_RESOURCE_TEST_TIMEOUT_MS='900000');result=subprocess.run([str(a.native.resolve()),str(app),a.origin],capture_output=True,timeout=950,env=env)
    (a.output/'native-public.log').write_bytes(result.stdout+result.stderr);assert result.returncode==0,(result.returncode,result.stderr[-2000:]);reply=json.loads(result.stdout.decode('utf8'));assert reply['ok'],reply
    destination=app/'resource_pak'/identity;files=[f for f in destination.rglob('*') if f.is_file()];milk=next(p for p in catalog['packs'] if p['id']==identity);assert len(files)==milk['fileCount'] and sum(f.stat().st_size for f in files)==milk['expandedBytes'];assert (app/'freekill.client.config.json').read_bytes()==private
    skins=json.loads((destination/'packages/freekill-core/image/xinyuesha-naisha/catalog.json').read_text('utf8')) if identity=='奶杀动皮-v1' else {'skins':[]}
    if identity=='奶杀动皮-v1':assert len(skins['skins'])==244
    for skin in skins['skins']:
        for key in ['idle','background','attack','skill']:
            if key in skin:
                for field in ['atlas','skeleton']:assert (destination/'packages/freekill-core/image/xinyuesha-naisha'/skin[key][field]).is_file()
report={'passed':True,'publicHttpObjectsVerified':len(rows),'publicHttpBytesVerified':sum(r['bytes'] for r in rows),'nativePublicInstallPack':identity,'nativePublicMilkInstall':identity=='奶杀动皮-v1','nativeResourceFiles':milk['fileCount'],'nativeSkinCount':len(skins['skins']),'accountSettingsUntouched':True,'deviceAcceptance':False,'sourceCommit':os.environ.get('GITHUB_SHA','local')};(a.output/'result.json').write_text(json.dumps(report,indent=2),'utf8');print(json.dumps(report))
