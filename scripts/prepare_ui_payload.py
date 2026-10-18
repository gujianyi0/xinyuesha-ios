#!/usr/bin/env python3
"""Version only the three managed UI directories, independent of FK_VERSION."""
from pathlib import Path
import hashlib
import sys

def prepare(runtime):
    runtime=Path(runtime)
    digest=hashlib.sha256()
    for name in ('Fk','LunarLtk','card-counter'):
        root=runtime/name
        if not root.is_dir(): raise ValueError(f'Missing managed directory: {name}')
        for path in sorted(p for p in root.rglob('*') if p.is_file()):
            if path.is_symlink(): raise ValueError('Symlinks are not managed UI files')
            digest.update(path.relative_to(runtime).as_posix().encode()+b'\0')
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    revision=digest.hexdigest()
    (runtime/'client-ui-revision').write_text(revision+'\n',encoding='ascii')
    return revision

if __name__=='__main__': print(prepare(sys.argv[1]))
