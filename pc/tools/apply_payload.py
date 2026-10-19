"""Apply only the published PC UI payload, preserving existing files in a backup."""
from pathlib import Path
import argparse, datetime, shutil

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir',type=Path,required=True)
    args=parser.parse_args()
    game=args.game_dir.resolve(strict=True)
    if not (game/'FreeKill.exe').is_file():parser.error('Target must contain FreeKill.exe; close the game before updating.')
    source=Path(__file__).resolve().parents[1]/'payload'
    backup=game/'assets/client-update-backup'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    changed=[]
    for file in source.rglob('*'):
        if not file.is_file():continue
        relative=file.relative_to(source)
        target=game/relative
        if not target.resolve().is_relative_to(game):raise RuntimeError('Target leaves the game directory')
        if target.is_file() and target.read_bytes()==file.read_bytes():continue
        if target.exists():
            saved=backup/relative;saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,saved)
        target.parent.mkdir(parents=True,exist_ok=True)
        stage=target.with_name(target.name+'.counter-update')
        if stage.is_symlink() or stage.exists():raise RuntimeError('Update staging path already exists')
        stage.write_bytes(file.read_bytes());stage.replace(target);changed.append(relative.as_posix())
    print('Updated',len(changed),'UI files. Existing configuration and package databases were not changed.')
    if changed:print('Backup:',backup)

if __name__=='__main__':main()
