"""Expand the three pinned v1 resource archives into a build-only runtime."""
import argparse,hashlib,json,re,stat,zipfile
from pathlib import Path,PurePosixPath
def prepare(catalog_path,archives,target):
    catalog=json.loads(Path(catalog_path).read_text(encoding='utf8'))
    expected={'手杀武将特效-v1','十周年特效-v1','指向线特效-v1'}
    assert catalog['schema']==1 and {r['id'] for r in catalog['packs']}==expected
    sha=lambda data:hashlib.sha256(data).hexdigest()
    result=[]
    for pack in catalog['packs']:
        assert re.fullmatch(r'[A-Za-z0-9_-]+\.zip',pack['archive'])
        data=(Path(archives)/pack['archive']).read_bytes()
        assert len(data)==pack['bytes'] and sha(data)==pack['sha256'],pack['archive']
        with zipfile.ZipFile(Path(archives)/pack['archive']) as z:
            files={i.filename:i for i in z.infolist() if not i.is_dir()}
            assert len(files)==len([i for i in z.infolist() if not i.is_dir()])
            assert {n:sha(z.read(n)) for n in files}=={r['path']:r['sha256'] for r in pack['files']}
            for name,info in files.items():
                parts=PurePosixPath(name)
                assert not parts.is_absolute() and '..' not in parts.parts and '\\' not in name
                assert not stat.S_ISLNK(info.external_attr>>16)
                dest=Path(target)/'resource_pak'/pack['id']/Path(*parts.parts)
                dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(z.read(name))
        manifest=next(r['path'] for r in pack['files'] if r['path'].endswith('/manifest.json'))
        result.append({'id':pack['id'],'requiredFile':manifest,'archiveSha256':pack['sha256']})
    marker=Path(target)/'card-counter/included-visual-packs.json';marker.parent.mkdir(parents=True,exist_ok=True)
    marker.write_text(json.dumps({'schema':1,'bundleId':catalog['bundleId'],'packs':result},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    return {'packs':len(result),'files':sum(len(r['files']) for r in catalog['packs']),'resourceBundleId':catalog['bundleId']}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--catalog',type=Path,required=True);p.add_argument('--archives',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args()
    print(json.dumps(prepare(a.catalog,a.archives,a.target)))
