#!/usr/bin/env python3
"""Version only the three managed UI directories, independent of FK_VERSION."""
from pathlib import Path
import hashlib
import sys

def prepare(runtime):
    runtime=Path(runtime)
    digest=hashlib.sha256()
    names=['Fk','LunarLtk','card-counter']
    if (runtime/'resource_pak').is_dir(): names.append('resource_pak')
    for name in names:
        root=runtime/name
        if not root.is_dir(): raise ValueError(f'Missing managed directory: {name}')
        # WindowsPath comparisons fold case; hash the same ordered paths on
        # every build host, including a local assembly of a macOS build.
        for path in sorted((p for p in root.rglob('*') if p.is_file()),
                           key=lambda p:p.relative_to(runtime).parts):
            if path.is_symlink(): raise ValueError('Symlinks are not managed UI files')
            digest.update(path.relative_to(runtime).as_posix().encode()+b'\0')
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    revision=digest.hexdigest()
    (runtime/'client-ui-revision').write_bytes((revision+'\n').encode('ascii'))
    return revision

if __name__=='__main__': print(prepare(sys.argv[1]))
