#!/usr/bin/env python3
"""Exercise the real seed bundle and exported metadata, without user data."""
from pathlib import Path
import subprocess
import tempfile
import os
import shutil
from prepare_core_repository import prepare, CORE_COMMIT, CORE_URL

with tempfile.TemporaryDirectory(prefix='fk-core-test-', dir=os.environ.get('FK_CORE_TEST_TMP')) as tmp:
    runtime = Path(tmp) / 'FreeKill.app/res'
    result = prepare(runtime)
    core = runtime / 'packages/freekill-core'
    assert result['commit'] == CORE_COMMIT and result['origin'] == CORE_URL
    assert result['clean']
    assert (core / 'Fk/main.qml').is_file()
    assert not (core / '.git/logs').exists()
    assert (core / '.git/refs/heads/master').is_file()
    config = (core / '.git/config').read_text()
    assert str(Path(tmp)) not in config and 'file:' not in config
    assert 'token' not in config.lower() and 'credential' not in config.lower()
    # Sideloaders can discard all empty directory entries from an IPA.
    copied = Path(tmp) / 'files-only'
    for source in core.rglob('*'):
        if source.is_file():
            target = copied / source.relative_to(core)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    subprocess.run(['git', '-C', str(copied), 'rev-parse', '--verify', 'HEAD^{commit}'], check=True)
    subprocess.run(['git', '-C', str(copied), 'fsck', '--full', '--no-reflogs'], check=True)
    subprocess.run(['git', '-C', str(core), 'fsck', '--full', '--no-reflogs'], check=True)
    # Rebuilding the same app payload must produce another complete repository.
    assert prepare(runtime)['commit'] == CORE_COMMIT
print('Seed packaging and metadata privacy checks passed.')
