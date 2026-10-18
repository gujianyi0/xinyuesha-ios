from pathlib import Path
import os
import stat
import tempfile
from zipfile import ZipFile
from package_ipa import package

with tempfile.TemporaryDirectory(prefix='ipa-pack-test-', dir=os.environ.get('FK_CORE_TEST_TMP')) as tmp:
    root = Path(tmp)
    app = root / 'Payload/FreeKill.app'
    app.mkdir(parents=True)
    (app / '中文资源.txt').write_bytes(b'unchanged resource bytes')
    (app / 'FreeKill').write_bytes(b'executable sentinel')
    (app / 'FreeKill').chmod(0o755)
    (app / '.git/refs/heads').mkdir(parents=True)
    if os.name != 'nt':
        (app / 'executable-link').symlink_to('FreeKill')
    archive = root / 'game.ipa'
    package(root, archive)
    with ZipFile(archive) as z:
        assert z.testzip() is None
        name = 'Payload/FreeKill.app/中文资源.txt'
        assert z.read(name) == b'unchanged resource bytes'
        assert z.getinfo(name).flag_bits & 0x800
        assert z.read('Payload/FreeKill.app/FreeKill') == b'executable sentinel'
        assert 'Payload/FreeKill.app/.git/refs/heads/' in z.namelist()
        if os.name != 'nt':
            link = z.getinfo('Payload/FreeKill.app/executable-link')
            assert stat.S_ISLNK(link.external_attr >> 16)
            assert z.read(link) == b'FreeKill'
print('IPA UTF-8 names, file contents, directory and link metadata checks passed.')
