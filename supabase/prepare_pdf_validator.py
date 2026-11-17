# SPDX-License-Identifier: AGPL-3.0-or-later
"""Prepare the separately licensed, disabled PDF service from a pinned official artifact.

Writes a NEW destination only. Does not deploy, configure providers or install
packages globally. The resulting vendor bytes stay out of the app/frontend.
"""
import argparse
import base64
import hashlib
import io
import shutil
import tarfile
import urllib.request
from pathlib import Path

VERSION = '1.28.6'
URL = 'https://registry.npmjs.org/mupdf/-/mupdf-'+VERSION+'.tgz'
SHA512 = 'LsNqk3a9TNJGjJKWVOUK1YMlWJNxFh8bIf+SSxGI+A+WXDlkwc4R2PW/n1qINb4YpqZfOazjPdRqw95WpmCrfw=='
FILES = ['LICENSE', 'package.json'] + ['dist/'+name for name in ['mupdf.js','mupdf.d.ts','mupdf-wasm.js','mupdf-wasm.d.ts','mupdf-wasm.wasm']]

def prepare(destination: Path, archive: bytes):
    if destination.exists(): raise ValueError('Destination already exists; existing work was preserved')
    if len(archive) > 20*1024*1024 or base64.b64encode(hashlib.sha512(archive).digest()).decode() != SHA512:
        raise ValueError('Official MuPDF artifact checksum mismatch')
    # Select named files only; never execute npm scripts or extract arbitrary paths.
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as bundle:
        entries = {name:bundle.getmember('package/'+name) for name in FILES}
        if any(not member.isfile() for member in entries.values()) or sum(m.size for m in entries.values()) > 32*1024*1024:
            raise ValueError('Unexpected pinned artifact structure')
        destination.mkdir(mode=0o700, parents=True)
        source = Path(__file__).resolve().parent/'functions/teamstats-pdf-validator'
        for name in ['index.ts','engine.ts','LICENSE','README.md']:
            shutil.copyfile(source/name,destination/name)
        vendor = destination/'vendor/mupdf'
        for name,member in entries.items():
            path=vendor/name;path.parent.mkdir(parents=True,exist_ok=True)
            with bundle.extractfile(member) as contents:path.write_bytes(contents.read())
    return destination

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--archive',type=Path,help='Optional already-downloaded artifact; the same checksum is mandatory')
    args=parser.parse_args()
    if args.output.exists():parser.error('Destination exists; choose a new destination')
    if args.archive:archive=args.archive.read_bytes()
    else:
        with urllib.request.urlopen(URL,timeout=30) as reply:archive=reply.read(20*1024*1024+1)
    prepare(args.output,archive)
    print('Prepared pinned PDF validation service; disabled until reviewed configuration. Nothing deployed.')
