"""Audit explicit .35 managed payloads, native baselines and private-file exclusions."""
import argparse, hashlib, json, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REV='20261126.35'
def digest(data): return hashlib.sha256(data).hexdigest()
def private_check(names):
    forbidden={'freekill.client.config.json','quick_start.json','auth.json','keypass.local','naisha-skins.json','client-before.private.json','function-settings.json'}
    assert not any(Path(n).name in forbidden or n.endswith(('.p12','.pfx','.key','.log')) or 'pc-smoke' in n for n in names), 'Private/test file included'
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--ios-baseline',type=Path,required=True);a=p.parse_args();rows=[]
    for platform,filename,source,prefix in [
        ('Android',f'新月杀-Android-{REV}.apk',ROOT/'android/payload','assets/res/'),
        ('PC',f'新月杀-PC-{REV}-x64.zip',ROOT/'pc/payload',''),
        ('iOS',f'新月杀-iOS-{REV}-unsigned.ipa',ROOT/'runtime','Payload/FreeKill.app/res/')]:
        file=a.output/filename
        with zipfile.ZipFile(file) as z:
            private_check(z.namelist())
            for folder in ['Fk','LunarLtk','card-counter']:
                if not (source/folder).is_dir():continue
                for f in (source/folder).rglob('*'):
                    if f.is_file() and f.name!='bundled-files.json':
                        assert z.read(prefix+f.relative_to(source).as_posix())==f.read_bytes(),str(f)
            catalog=json.loads(z.read(prefix+'card-counter/resource-catalog.json'))
            assert len(catalog['packs'])==4
            milk=next(p for p in catalog['packs'] if p['id']=='奶杀动皮-v1');assert len(milk['parts'])==12 and milk['fileCount']==1840
            if platform=='Android':
                manifest=json.loads(z.read(prefix+'card-counter/bundled-files.json'));assert len(manifest)==30
                assert all(digest(z.read(prefix+n))==h for n,h in manifest.items())
                with zipfile.ZipFile(ROOT.parent/'特效补丁/v1/20261126.34-奶杀接入候选/新月杀-Android-20261126.34.apk') as old:
                    assert all(z.read(n)==old.read(n) for n in old.namelist() if n.startswith('lib/'))
                embedded=json.loads(z.read('assets/embedded-effects/catalog.json'));assert len(embedded['packs'])==3
                for pack in embedded['packs']:assert digest(z.read('assets/embedded-effects/'+pack['archive']))==pack['sha256']
            elif platform=='PC':
                assert z.read('FreeKill.exe')==Path('F:/tmp/newmoon-native-35/build/FreeKill.exe').read_bytes()
                old=Path('F:/tmp/newmoon-native-33/portable')
                for n in z.namelist():
                    if n.startswith('packages/freekill-core/') or n.endswith('.dll'):assert z.read(n)==(old/n).read_bytes(),n
            else:
                with zipfile.ZipFile(a.ios_baseline) as old:
                    assert not set(old.namelist())-set(z.namelist())
                    for n in old.namelist():
                        managed=n.startswith(tuple(prefix+d+'/' for d in ['Fk','LunarLtk','card-counter'])) or n==prefix+'client-ui-revision'
                        if not managed:assert z.read(n)==old.read(n),n
                    assert z.read('Payload/FreeKill.app/FreeKill')!=zipfile.ZipFile(ROOT.parent/'特效补丁/v1/20261126.34-奶杀接入候选/新月杀-iOS-20261126.34-unsigned.ipa').read('Payload/FreeKill.app/FreeKill')
            rows.append({'platform':platform,'passed':True,'privateDataIncluded':False,'onlineMilkParts':12,'bytes':file.stat().st_size,'sha256':hashlib.file_digest(file.open('rb'),'sha256').hexdigest()})
    report={'passed':True,'revision':REV,'deviceAcceptance':False,'platforms':rows}
    (a.output/'三端包审计.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n','utf8');print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
