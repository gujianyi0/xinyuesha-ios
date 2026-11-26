"""Build .35 clients from pristine native baselines and explicit managed UI."""
import argparse, hashlib, json, os, shutil, subprocess, zipfile
from pathlib import Path
from prepare_ui_payload import prepare

ROOT = Path(__file__).resolve().parents[1]
REV = '20261126.35'

def copy_ui(source, destination):
    for folder in ['Fk', 'LunarLtk', 'card-counter']:
        if (source / folder).is_dir():
            shutil.copytree(source / folder, destination / folder, dirs_exist_ok=True)
    prepare(destination)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--stage', type=Path, required=True)
    p.add_argument('--platform', choices=['android', 'pc', 'ios'], required=True)
    p.add_argument('--ios-baseline', type=Path)
    p.add_argument('--resume', action='store_true')
    a = p.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
    a.stage.mkdir(parents=True, exist_ok=True)
    if a.platform == 'android':
        subprocess.run([os.sys.executable, str(ROOT/'android/tools/build_apk.py'),
            '--baseline', str(ROOT.parent/'特效补丁/v1/20261126.34-奶杀接入候选/新月杀-Android-20261126.34.apk'),
            '--keystore', 'C:/Users/c2115/Documents/ChatGPT/other/work/freekill-card-counter/standalone/signing/counter.p12',
            '--storepass-file', 'C:/Users/c2115/Documents/ChatGPT/other/work/freekill-card-counter/standalone/signing/keypass.local',
            '--embedded-resource-catalog', str(ROOT/'work/embedded-v1-20261121/assets/catalog.json'),
            '--output', str(a.output/f'新月杀-Android-{REV}.apk')], cwd=ROOT, check=True)
    elif a.platform == 'pc':
        portable = a.stage/'portable'
        if portable.exists() and not a.resume: raise RuntimeError('Use a fresh PC staging directory')
        if not portable.exists(): shutil.copytree('F:/tmp/newmoon-native-33/portable', portable)
        shutil.copyfile('F:/tmp/newmoon-native-35/build/FreeKill.exe', portable/'FreeKill.exe')
        copy_ui(ROOT/'pc/payload', portable)
        (portable/'候选版说明.txt').write_text(f'新月杀 {REV} 资源包下载候选\n管理资源包：奶杀动皮可直接下载，完成后默认启用；×停用，左侧删除。\n奶杀包下载约 1.31 GB，安装约 1.45 GB；建议预留 3 GB。\n下载资源包后，可在功能设置 → 奶杀动皮选择已适配皮肤。\n不含个人账号或设置；未经本轮真机、主力服回归验收。\n', encoding='utf8')
        with zipfile.ZipFile(a.output/f'新月杀-PC-{REV}-x64.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=5) as z:
            for f in sorted(portable.rglob('*')):
                if f.is_file(): z.write(f, f.relative_to(portable).as_posix())
    else:
        if not a.ios_baseline: p.error('--ios-baseline is required')
        prefix = 'Payload/FreeKill.app/res/'
        stage = a.stage/'ios-res'; stage.mkdir(exist_ok=False)
        with zipfile.ZipFile(a.ios_baseline) as old:
            for item in old.infolist():
                if item.filename.startswith(prefix) and not item.is_dir():
                    rel = Path(item.filename[len(prefix):])
                    assert not rel.is_absolute() and '..' not in rel.parts
                    if rel.parts[0] in ['Fk', 'LunarLtk', 'card-counter', 'resource_pak']:
                        dest = stage/rel; dest.parent.mkdir(parents=True, exist_ok=True); dest.write_bytes(old.read(item))
            # Native baseline is the actual .35 cloud build, never a QML-only .34 IPA.
            assert b'gujianyi-xinyuesha-resources.pages.dev' in old.read('Payload/FreeKill.app/FreeKill')
            copy_ui(ROOT/'runtime', stage)
            overrides = {prefix+f.relative_to(stage).as_posix(): f for f in stage.rglob('*') if f.is_file()}
            with zipfile.ZipFile(a.output/f'新月杀-iOS-{REV}-unsigned.ipa', 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as new:
                present = set()
                for item in old.infolist():
                    new.writestr(item, overrides[item.filename].read_bytes() if item.filename in overrides else old.read(item)); present.add(item.filename)
                for name, f in overrides.items():
                    if name not in present: new.write(f, name)
    print(json.dumps({'platform': a.platform, 'revision': REV, 'deviceAcceptance': False}))

if __name__ == '__main__': main()
