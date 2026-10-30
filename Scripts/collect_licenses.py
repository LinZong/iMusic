#!/usr/bin/env python3
"""Collect notices from the exact resolved package checkouts, without running package code."""
import json
import shutil
from pathlib import Path
root = Path(__file__).resolve().parents[1]
out = root / 'ThirdPartyNotices'
out.mkdir(exist_ok=True)
pins = json.loads((root / 'Package.resolved').read_text())['pins']
(out / 'DEPENDENCIES.json').write_text(json.dumps(pins, indent=2) + '\n')
checkouts = root / '.build/checkouts'
for checkout in sorted(checkouts.iterdir()):
    if not checkout.is_dir():
        continue
    notices = [p for p in checkout.iterdir() if p.is_file() and (p.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE', 'ACKNOWLEDGMENT')))]
    for notice in notices:
        directory = out / checkout.name
        directory.mkdir(exist_ok=True)
        shutil.copyfile(notice, directory / notice.name)
web = root / 'Web/WiFiUpload'
lock = json.loads((web / 'package-lock.json').read_text())
runtime = {}
for name, entry in lock['packages'].items():
    if name and not entry.get('dev'):
        package = name.removeprefix('node_modules/')
        runtime[package] = {key: entry[key] for key in ('version', 'resolved', 'integrity', 'license') if key in entry}
        directory = out / 'Web' / package
        directory.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(web / name / 'LICENSE', directory / 'LICENSE')
(out / 'WEB_DEPENDENCIES.json').write_text(json.dumps(runtime, indent=2) + '\n')
(out / 'README.md').write_text('''# Third-party notices

These files accompany the exact dependency graph recorded in DEPENDENCIES.json and Package.resolved.
The MIT license for iMusic does not replace these component licenses.
SFBAudioEngine includes components under additional licenses, including LGPL; its ACKNOWLEDGMENTS.md is included.
When distributing binaries, provide the corresponding pinned component sources, build instructions and any required relinking materials. Do not distribute only this notice directory as a substitute for those materials.
Source repositories and revisions are listed in DEPENDENCIES.json. The application and build scripts are available as source; package sources are obtained by `swift package resolve`.
React, React DOM and Scheduler runtime licenses are in Web/ and are also bundled as upload-licenses.txt.\nTheir exact npm versions and integrity hashes are in WEB_DEPENDENCIES.json and Web/WiFiUpload/package-lock.json.\nRun `npm ci --prefix Web/WiFiUpload` and `python3 Scripts/collect_licenses.py` after changing either lockfile.
''')
