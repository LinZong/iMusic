"""Shared command execution and locked web dependencies for Apple build scripts."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
from typing import Sequence


# Resolve paths from the checkout instead of the caller's working directory.
ROOT = Path(__file__).resolve().parents[1]


class BuildError(Exception):
    """Describe an actionable build, signing, or deployment failure."""


class CommandError(BuildError):
    """Retain command output and its log location for platform-specific diagnostics."""

    def __init__(self, command: Sequence[str], output: str, log: Path):
        """Store the failure without losing its full diagnostic log."""
        self.output = output
        self.log = log
        tail = "\n".join(output.splitlines()[-20:])
        super().__init__(f"{command[0]} failed. Log: {log}\n{tail}")


class Runner:
    """Run argument arrays without a shell and save diagnostics outside tracked files."""

    def __init__(self, directory: Path):
        """Create the per-run log directory before invoking external tools."""
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)
        self.index = 0

    def run(self, command: Sequence[str], label: str, timeout: int | None = None) -> str:
        """Capture stdout/stderr together, raising a readable error on failure."""
        self.index += 1
        log = self.directory / f"{self.index:02d}-{label}.log"
        try:
            result = subprocess.run(
                list(command), cwd=ROOT, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, errors="replace", timeout=timeout,
            )
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            log.write_text(output)
            raise BuildError(
                f"{label} timed out. Log: {log}"
            ) from error
        except OSError as error:
            raise BuildError(f"Cannot run {command[0]}: {error}") from error
        log.write_text(result.stdout)
        if result.returncode:
            raise CommandError(command, result.stdout, log)
        return result.stdout


def tool(name: str) -> str | None:
    """Find a tool on PATH or in the usual Apple Silicon/Intel Homebrew locations."""
    found = shutil.which(name)
    if found:
        return found
    for directory in ("/opt/homebrew/bin", "/usr/local/bin"):
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def prepare_web(runner: Runner) -> None:
    """Use the npm lockfile so release assets cannot silently use stale dependencies."""
    node = os.environ.get("NODE_BINARY") or tool("node")
    npm = tool("npm")
    if not node or not npm:
        raise BuildError(
            "Node.js 22.12+ and npm are required to build the bundled upload client."
        )
    version = runner.run([node, "-p", "process.versions.node"], "node-version", timeout=15)
    parts = tuple(int(part) for part in version.strip().split(".")[:2])
    if parts < (22, 12):
        raise BuildError(
            "Node.js 22.12+ is required. Activate a supported Node version and retry."
        )
    # npm and Xcode's build plugin must resolve the same active Node executable.
    os.environ["PATH"] = str(Path(node).parent) + os.pathsep + os.environ.get("PATH", "")
    os.environ["NODE_BINARY"] = node
    print("Installing upload-client dependencies from package-lock.json...", flush=True)
    runner.run([
        npm, "ci", "--prefix", str(ROOT / "Web/WiFiUpload"), "--no-audit", "--no-fund",
    ], "npm-ci")
