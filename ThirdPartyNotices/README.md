# Third-party notices

These files accompany the exact dependency graph recorded in DEPENDENCIES.json and Package.resolved.
The MIT license for iMusic does not replace these component licenses.
SFBAudioEngine includes components under additional licenses, including LGPL; its ACKNOWLEDGMENTS.md is included.
When distributing binaries, provide the corresponding pinned component sources, build instructions and any required relinking materials. Do not distribute only this notice directory as a substitute for those materials.
Source repositories and revisions are listed in DEPENDENCIES.json. The application and build scripts are available as source; package sources are obtained by `swift package resolve`.
React, React DOM and Scheduler runtime licenses are in Web/ and are also bundled as upload-licenses.txt.
Their exact npm versions and integrity hashes are in WEB_DEPENDENCIES.json and Web/WiFiUpload/package-lock.json.
Run `npm ci --prefix Web/WiFiUpload` and `python3 Scripts/collect_licenses.py` after changing either lockfile.
