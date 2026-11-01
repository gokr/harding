#!/usr/bin/env python3
"""Build pinned stock Cog/Oil VMs locally for matched-image comparisons.

No system installation. Requires clang/make and platform development headers.
Downloads/builds stay under build/osvm; missing dependencies fail in saved logs.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REVISION = '0310be549c0139d972c21a6e67e48803c3fa9843'
IMAGE_URL = 'https://files.squeak.org/6.1/Squeak6.1-23976-64bit/Squeak6.1-23976-64bit.zip'
IMAGE_SHA256 = '0672833a22134810c69d7a595ad7d639ea76e49cb2ac72676a4ff7f928683410'
FLAVORS = {'cog': 'sqcogspur64linuxht', 'oil': 'sqoilspur64linuxht'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flavor', choices=('cog', 'oil', 'both'), default='both')
    args = parser.parse_args()
    work = ROOT / 'build/osvm'
    work.mkdir(parents=True, exist_ok=True)
    repo = work / 'repo'
    if not repo.exists():
        subprocess.run(['git', 'init', str(repo)], check=True)
        subprocess.run(['git', 'remote', 'add', 'origin',
                        'https://github.com/OpenSmalltalk/opensmalltalk-vm.git'], cwd=repo, check=True)
        subprocess.run(['git', 'fetch', '--depth', '1', 'origin', REVISION], cwd=repo, check=True)
        subprocess.run(['git', 'checkout', '--detach', 'FETCH_HEAD'], cwd=repo, check=True)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    if revision != REVISION:
        raise RuntimeError('Refusing to change existing checkout; expected ' + REVISION)
    subprocess.run(['./scripts/updateSCCSVersions'], cwd=repo, check=True)
    for flavor in (FLAVORS if args.flavor == 'both' else [args.flavor]):
        build = repo / 'building/linux64x64' / ('squeak.' + flavor + '.spur') / 'build'
        if (build / 'Makefile').exists():
            with (work / (flavor + '-clean.log')).open('w') as log:
                subprocess.run(['make', 'reallyclean'], cwd=build, stdout=log,
                               stderr=subprocess.STDOUT, check=True)
        # mvm caches configure in config.h; never silently reuse old flags.
        (build / 'config.h').unlink(missing_ok=True)
        (build / 'Makefile').unlink(missing_ok=True)
        environment = dict(os.environ, CFLAGS='-Wno-int-conversion -Wno-implicit-function-declaration')
        with (work / (flavor + '-build.log')).open('w') as log:
            subprocess.run(['./mvm'], input='n\n', cwd=build, env=environment, text=True,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        print('Built:', repo / 'products' / FLAVORS[flavor], flush=True)
    image_dir = work / 'image'
    image_dir.mkdir(exist_ok=True)
    archive = image_dir / 'Squeak6.1-23976-64bit.zip'
    if not archive.exists():
        with urllib.request.urlopen(IMAGE_URL, timeout=60) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != IMAGE_SHA256:
        raise RuntimeError('Squeak image archive hash mismatch')
    # Do not overwrite an existing image or its changes file.
    with zipfile.ZipFile(archive) as contents:
        for name in ('Squeak6.1-23976-64bit.image', 'Squeak6.1-23976-64bit.changes', 'SqueakV60.sources'):
            target = image_dir / name
            if not target.exists():
                with contents.open(name) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output)
    print('Image:', image_dir / 'Squeak6.1-23976-64bit.image')


if __name__ == '__main__':
    main()
