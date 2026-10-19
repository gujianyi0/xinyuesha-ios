"""Compile the testing edition's helper DEX without changing compiled strings.

Qt's superclass is represented by a compile-only ABI stub. The original Qt
classes.dex is retained by build_separate_app.py; no stub enters the APK.
"""
from pathlib import Path
import os
import subprocess
import tempfile

BASE = Path(__file__).resolve().parents[1]
SDK = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'AppData/Local/Android/Sdk')))
JDK = Path(os.environ.get('JAVA_HOME', r'C:\Program Files\Android\openjdk\jdk-21.0.8')) / 'bin'
TOOLS = SDK / 'build-tools/36.0.0'
ANDROID = SDK / 'platforms/android-36/android.jar'
BUILD = BASE / 'build'
BUILD.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix='compile-', dir=BUILD) as temporary:
    root = Path(temporary).resolve()
    assert root.is_relative_to(BUILD.resolve())
    classes = root / 'classes'
    classes.mkdir()
    stub = root / 'QtActivity.java'
    stub.write_text(
        'package org.qtproject.qt.android.bindings; '
        'public class QtActivity extends android.app.Activity { '
        'public void onCreate(android.os.Bundle b) { super.onCreate(b); } public void onDestroy() { super.onDestroy(); } }',
        encoding='utf-8',
    )
    # The background-service experiment is archived separately. It did not
    # prevent vendor freezing and must not enter distributed DEX files.
    sources = [BASE / 'java/org/notify/FreeKill' / (name + '.java')
               for name in ('CounterRepoRepair', 'CounterStartup', 'CounterPackageSources', 'CounterBackgroundImages', 'GameActivity')]
    subprocess.run([
        str(JDK / 'javac.exe'), '-encoding', 'UTF-8', '-source', '8', '-target', '8',
        '-classpath', str(ANDROID), '-d', str(classes), *map(str, sources), str(stub),
    ], check=True)
    dex = root / 'dex'
    dex.mkdir()
    own_classes = sorted((classes / 'org/notify/FreeKill').glob('*.class'))
    assert own_classes
    subprocess.run([
        str(JDK / 'java.exe'), '-cp', str(TOOLS / 'lib/d8.jar'), 'com.android.tools.r8.D8',
        '--lib', str(ANDROID), '--min-api', '28', '--output', str(dex),
        *map(str, own_classes),
    ], check=True)
    from dex_validation import validate_dex
    data = (dex / 'classes.dex').read_bytes()
    validate_dex(data)
    (BASE / 'build').mkdir(exist_ok=True)
    (BASE / 'build/classes.dex').write_bytes(data)
print('Helper DEX compiled and validated; Qt stub excluded.')
