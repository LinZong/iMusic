#!/usr/bin/env python3
"""Check concrete dependency boundaries; this is not a proof of every SOLID design property."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources" / "iMusicKit"


def violations() -> list[str]:
    """Detect infrastructure imports and direct persistence leaking into presentation code."""
    errors: list[str] = []
    forbidden_imports = {
        "Domain": {"SwiftUI", "UIKit", "AppKit", "GRDB", "CloudKit", "SFBAudioEngine"},
        "View": {"GRDB", "CloudKit", "SFBAudioEngine", "NIOCore", "NIOHTTP1"},
        "ViewModel": {"SwiftUI", "UIKit", "AppKit", "GRDB", "NIOCore", "NIOHTTP1"},
    }
    for layer, blocked in forbidden_imports.items():
        for path in (SOURCE / layer).rglob("*.swift"):
            for line_number, line in enumerate(path.read_text().splitlines(), 1):
                code = line.strip()
                if code.startswith("//"):
                    continue
                imported = re.match(r"import\s+(\w+)", code)
                if imported and imported.group(1) in blocked:
                    errors.append(f"{path.relative_to(ROOT)}:{line_number}: "
                                  f"{layer} must not import {imported.group(1)}")
                if layer == "View" and re.search(r"\.(store|database)\b", code):
                    errors.append(f"{path.relative_to(ROOT)}:{line_number}: "
                                  "Views must invoke feature commands instead of persistence")
    for name in (
        "View/Library/SongList/SongListView.swift",
        "View/Library/SongList/SongListPage.swift",
        "View/Library/SongList/GlassSongListPageContent.swift",
        "View/Library/SongList/GlassSongListContent.swift",
        "View/Library/CollectionGrid.swift",
    ):
        path = SOURCE / name
        if re.search(r"\b(LibraryDestination|CollectionKind)\b", path.read_text()):
            errors.append(f"{path.relative_to(ROOT)}: generic layout must not dispatch feature routes")
    return errors


def main() -> int:
    """Report architectural leaks with file/line diagnostics suitable for local runs and CI."""
    errors = violations()
    if errors:
        print("\n".join(errors))
        return 1
    print("Architecture boundaries passed: domain, views, view models, and generic list/grid layouts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
