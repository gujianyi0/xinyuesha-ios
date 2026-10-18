#!/usr/bin/env python3
"""Exercise the real seed bundle and exported metadata, without user data."""
from pathlib import Path
import subprocess
import tempfile
import os
from prepare_core_repository import prepare, CORE_COMMIT, CORE_URL

with tempfile.TemporaryDirectory(prefix='fk-core-test-', dir=os.environ.get('FK_CORE_TEST_TMP')) as tmp:
    runtime = Path(tmp) / 'FreeKill.app/res'
    result = prepare(runtime)
    core = runtime / 'packages/freekill-core'
    assert result['commit'] == CORE_COMMIT and result['origin'] == CORE_URL
    assert result['clean']
    assert (core / 'Fk/main.qml').is_file()
    assert not (core / '.git/logs').exists()
    config = (core / '.git/config').read_text()
    assert str(Path(tmp)) not in config and 'file:' not in config
    assert 'token' not in config.lower() and 'credential' not in config.lower()
    subprocess.run(['git', '-C', str(core), 'fsck', '--full', '--no-reflogs'], check=True)
    # Rebuilding the same app payload must produce another complete repository.
    assert prepare(runtime)['commit'] == CORE_COMMIT
print('Seed packaging and metadata privacy checks passed.')
