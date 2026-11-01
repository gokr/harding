#!/usr/bin/env python3
"""Build pinned GNU Smalltalk locally; never installs system packages.

Requires GNU awk, C build tools and libffi headers. Put any locally extracted
build dependencies on PATH/LD_LIBRARY_PATH before running. Logs and installation
stay under build/gnu-smalltalk. GNU Smalltalk is an optional benchmark dependency.
"""
import hashlib
from pathlib import Path
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SHA256 = '06e574e818ec49f0555d948ae53b1453d8c1df59ef597dad911a4fd1ffba1cce'
URL = 'https://ftp.gnu.org/gnu/smalltalk/smalltalk-3.2.5.tar.gz'


def main():
    work = ROOT / 'build/gnu-smalltalk'
    work.mkdir(parents=True, exist_ok=True)
    archive = work / 'smalltalk-3.2.5.tar.gz'
    if not archive.exists():
        with urllib.request.urlopen(URL, timeout=60) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError('GNU Smalltalk archive hash mismatch')
    source = work / 'smalltalk-3.2.5'
    if not source.exists():
        with tarfile.open(archive) as contents:
            contents.extractall(work, filter='data')
    commands = [
        ('configure', [str(source / 'configure'), '--prefix=' + str(work / 'install'),
                       '--disable-gtk', '--without-emacs',
                       'CFLAGS=-O2 -fcommon -Wno-error=implicit-function-declaration']),
        ('make', ['make', '-j4']), ('install', ['make', 'install'])]
    for label, command in commands:
        with (work / (label + '.log')).open('w') as log:
            subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT, check=True)
    print(work / 'install/bin/gst')


if __name__ == '__main__':
    main()
