#!/usr/bin/env python3
"""Write a portable IPA with explicit UTF-8 names and POSIX link metadata."""
from pathlib import Path
import os
import stat
import sys
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED


def package(root, destination):
    root = Path(root).resolve()
    destination = Path(destination).resolve()
    if not (root / 'Payload').is_dir() or destination.is_relative_to(root / 'Payload'):
        raise ValueError('Expected an IPA staging root containing Payload')
    with ZipFile(destination, 'w', ZIP_DEFLATED) as archive:
        for current, directories, files in os.walk(root / 'Payload', followlinks=False):
            for name in sorted(directories + files):
                path = Path(current) / name
                relative = path.relative_to(root).as_posix()
                if path.is_symlink():
                    entry = ZipInfo(relative)
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    entry.compress_type = ZIP_DEFLATED
                    archive.writestr(entry, os.readlink(path).encode('utf-8'))
                else:
                    archive.write(path, relative)


if __name__ == '__main__':
    package(sys.argv[1], sys.argv[2])
