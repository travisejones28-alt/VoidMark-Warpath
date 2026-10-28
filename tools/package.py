#!/usr/bin/env python3
"""Deterministic installation ZIP; excludes all development and obsolete files."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib
root = Path(__file__).resolve().parents[1]
files = ['VoidMarkWarpath.toc', 'VoidMarkWarpath_Camelot.toc']
files += [x for x in (root / files[0]).read_text().splitlines() if x and not x.startswith('#')]
files += ['README.md', 'NOTICE.md', 'docs/API-AUDIT.md', 'docs/TESTING.md', 'docs/RELEASE.md']
assert len(files) == len(set(files))
out = root / 'dist' / 'Warpath-1.0.0-alpha.1.zip'
out.parent.mkdir(exist_ok=True)
with ZipFile(out, 'w', compression=ZIP_DEFLATED) as z:
    for name in files:
        info = ZipInfo('VoidMarkWarpath/' + name, (2026, 10, 28, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        z.writestr(info, (root / name).read_bytes())
with ZipFile(out) as z:
    assert z.testzip() is None
    assert z.namelist() == ['VoidMarkWarpath/' + n for n in files]
    for name in files: assert z.read('VoidMarkWarpath/' + name) == (root / name).read_bytes()
print(str(out))
print('PASS: single addon folder, %d members, exact byte validation' % len(files))
print('SHA256 ' + hashlib.sha256(out.read_bytes()).hexdigest())
