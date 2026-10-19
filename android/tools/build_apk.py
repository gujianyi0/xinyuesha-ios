"""Package the published testing-edition payload with a matching native baseline."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, tempfile, zipfile
from dex_validation import validate_dex

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--keystore', type=Path, required=True)
    parser.add_argument('--storepass-file', type=Path, required=True)
    parser.add_argument('--store-type', default='PKCS12')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
    tools = sdk / 'build-tools/36.0.0'
    suffix = '.exe' if os.name == 'nt' else ''
    java = Path(os.environ['JAVA_HOME']) / 'bin' / ('java' + suffix)
    dex = (root / 'build/classes.dex').read_bytes()
    validate_dex(dex)
    payload = {p.relative_to(root/'payload').as_posix():p.read_bytes()
               for p in (root/'payload').rglob('*') if p.is_file()}
    manifest = json.loads(payload.pop('card-counter/bundled-files.json'))
    assert all(name in payload for name in manifest), 'Incomplete published payload'
    for name in manifest:
        manifest[name] = hashlib.sha256(payload[name]).hexdigest()
    payload['card-counter/bundled-files.json'] = json.dumps(manifest, sort_keys=True, indent=2).encode()
    build = root/'build';build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='package-', dir=build) as temporary:
        directory = Path(temporary)
        unsigned, aligned, signed = [directory/name for name in ('unsigned.apk','aligned.apk','signed.apk')]
        with zipfile.ZipFile(args.baseline) as old, zipfile.ZipFile(unsigned,'w') as new:
            assert 'com.cui.freekill.ds'.encode('utf-16le') in old.read('AndroidManifest.xml'), 'Wrong native baseline'
            present = set()
            for item in old.infolist():
                name = item.filename
                if name.startswith('META-INF/') and name.upper().endswith(('.SF','.MF','.RSA','.DSA','.EC')):
                    continue
                data = old.read(name)
                if name == 'classes2.dex':data = dex
                elif name.startswith('assets/res/') and name[11:] in payload:
                    relative = name[11:];data = payload[relative];present.add(relative)
                new.writestr(item,data)
            for relative,data in payload.items():
                if relative not in present:new.writestr('assets/res/'+relative,data,compress_type=zipfile.ZIP_DEFLATED)
        def run(*command):subprocess.run(list(map(str,command)),check=True)
        run(tools/('zipalign'+suffix),'-P','16','-f','4',unsigned,aligned)
        signer=[java,'-jar',tools/'lib/apksigner.jar']
        run(*signer,'sign','--ks',args.keystore.resolve(),'--ks-type',args.store_type,
            '--ks-pass','file:'+str(args.storepass_file.resolve()),'--v4-signing-enabled','false','--out',signed,aligned)
        run(*signer,'verify','--verbose',signed)
        run(tools/('zipalign'+suffix),'-c','-P','16','4',signed)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(signed,args.output)
    print('APK:',args.output,'SHA256:',hashlib.sha256(args.output.read_bytes()).hexdigest())

if __name__ == '__main__':main()
