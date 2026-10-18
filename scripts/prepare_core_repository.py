#!/usr/bin/env python3
"""Restore a portable, verified core Git repository into an iOS .app.

The bundle contains upstream Git objects only, not a developer's .git/config,
credentials, hooks or reflogs. A fresh clone supplies portable metadata.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / 'scripts/assets/freekill-core.bundle'
CORE_COMMIT = '9f5c0bdbc8733c39be1a807c9853917c399ef57b'
CORE_URL = 'https://gitee.com/Qsgs-Fans/freekill-core'


def git(*args, cwd=None):
    return subprocess.check_output(['git', *map(str, args)], cwd=cwd,
                                   stderr=subprocess.PIPE).decode().strip()


def prepare(runtime, bundle=SEED, commit=CORE_COMMIT):
    runtime = Path(runtime).resolve()
    target = runtime / 'packages/freekill-core'
    if runtime.name != 'res' or runtime.parent.suffix != '.app':
        raise ValueError('Only a built .app/res payload may be prepared')
    if target.is_symlink() or not target.resolve().is_relative_to(runtime):
        raise ValueError('Core payload escapes the app runtime')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='core-seed-', dir=target.parent) as tmp:
        repo = Path(tmp) / 'repository'
        git('-c', 'core.autocrlf=false', 'clone', '--no-checkout', bundle.resolve(), repo)
        git('-C', repo, 'config', 'core.autocrlf', 'false')
        git('-C', repo, 'checkout', '--detach', commit)
        # IPA repackers may omit empty directories. Keep refs nonempty so a
        # files-only extraction still satisfies Git's repository layout.
        git('-C', repo, 'update-ref', 'refs/heads/master', commit)
        git('-C', repo, 'remote', 'set-url', 'origin', CORE_URL)
        git('-C', repo, 'fsck', '--full', '--no-reflogs')
        if git('-C', repo, 'status', '--porcelain', '--untracked-files=all'):
            raise RuntimeError('Core worktree is not clean')
        # Remove local build paths and incidental clone metadata before sharing.
        for name in ('logs', 'hooks'):
            shutil.rmtree(repo / '.git' / name, ignore_errors=True)
        for name in ('FETCH_HEAD', 'ORIG_HEAD'):
            (repo / '.git' / name).unlink(missing_ok=True)
        if target.exists():
            def writable_retry(function, path, error):
                Path(path).chmod(stat.S_IWRITE | stat.S_IREAD)
                function(path)
            shutil.rmtree(target, onerror=writable_retry)
        shutil.move(str(repo), target)
    db = runtime / 'packages/packages.db'
    if db.exists():
        with sqlite3.connect(db) as con:
            con.execute('UPDATE packages SET url=?,hash=? WHERE name=?',
                        (CORE_URL, commit, 'freekill-core'))
    report = {'commit': git('-C', target, 'rev-parse', 'HEAD'),
              'origin': git('-C', target, 'remote', 'get-url', 'origin'),
              'bundle_sha256': hashlib.sha256(bundle.read_bytes()).hexdigest(),
              'clean': not git('-C', target, 'status', '--porcelain')}
    print(json.dumps(report))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runtime', type=Path, help='Built .app/res directory (not user data)')
    args = parser.parse_args()
    prepare(args.runtime)
