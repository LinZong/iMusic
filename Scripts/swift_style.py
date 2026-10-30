#!/usr/bin/env python3
"""Format or check first-party Swift files with the selected Xcode toolchain."""

from pathlib import Path
import argparse
import json
import subprocess
import sys


def swift_files(root: Path) -> list[Path]:
    """Include tracked and unignored new Swift files without traversing build caches."""
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.swift"],
        cwd=root,
        check=True,
        capture_output=True,
    )
    return sorted(
        {
            root / name.decode("utf-8")
            for name in result.stdout.split(b"\0")
            if name and (root / name.decode("utf-8")).is_file()
        }
    )


def check_line_lengths(paths: list[Path], root: Path, limit: int) -> bool:
    """Enforce the column budget even for comments and literals the formatter cannot split."""
    valid = True
    for path in paths:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            width = len(line.expandtabs(4))
            if width > limit:
                print(
                    f"{path.relative_to(root)}:{number}: error: "
                    f"[LineLength] {width} characters exceeds the {limit}-character limit. "
                    "Wrap comments or use a multiline literal with escaped line breaks.",
                    file=sys.stderr,
                )
                valid = False
    return valid


def main() -> int:
    """Run the formatter when requested and always finish with strict, read-only checks."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("format", "check"))
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    configuration = root / ".swift-format"
    try:
        tool = subprocess.check_output(
            ["xcrun", "--find", "swift-format"], text=True, stderr=subprocess.PIPE
        ).strip()
        version = subprocess.check_output([tool, "--version"], text=True).strip()
        paths = swift_files(root)
    except (OSError, subprocess.CalledProcessError) as error:
        print(
            f"error: Swift style checks require Git and Xcode with swift-format. {error}",
            file=sys.stderr,
        )
        return 1

    print(f"swift-format {version}; {len(paths)} first-party Swift files", flush=True)
    if not paths:
        print("error: No Swift source files found.", file=sys.stderr)
        return 1

    shared = ["--configuration", str(configuration), "--parallel"]
    if arguments.mode == "format":
        result = subprocess.run([tool, "format", "--in-place", *shared, *map(str, paths)])
        if result.returncode:
            return result.returncode

    result = subprocess.run([tool, "lint", "--strict", *shared, *map(str, paths)])
    limit = json.loads(configuration.read_text())["lineLength"]
    lengths_valid = check_line_lengths(paths, root, limit)
    if result.returncode or not lengths_valid:
        return 1
    print(f"Swift style passed: all lines fit within {limit} characters.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
