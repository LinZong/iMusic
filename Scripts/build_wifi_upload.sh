#!/bin/sh
# SwiftPM invokes this in its sandbox. Dependencies are installed once with npm ci.
set -eu
root="$1"
work="$2"
node_home="${HOME:-${IMUSIC_NODE_HOME:-}}"
export PATH="${node_home}/.volta/bin:${node_home}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export VOLTA_HOME="${VOLTA_HOME:-${node_home}/.volta}"
node_bin="${NODE_BINARY:-$(command -v node || true)}"
node_works() {
    [ -x "$1" ] && "$1" -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 12) ? 0 : 1)' >/dev/null 2>&1
}
if [ -z "${NODE_BINARY:-}" ] && ! node_works "$node_bin"; then
    # Xcode launched from Finder does not source nvm's shell setup.
    node_bin=$(for candidate in "$node_home"/.nvm/versions/node/*/bin/node /opt/homebrew/bin/node /usr/local/bin/node; do
        if node_works "$candidate"; then printf '%s\n' "$candidate"; fi
    done | sort -V | tail -n 1)
fi
if ! node_works "$node_bin"; then
    echo 'error: Node.js 22.12+ is required to build Wi-Fi Upload. Install Node or set NODE_BINARY.' >&2
    exit 1
fi
if [ ! -f "$root/Web/WiFiUpload/node_modules/vite/bin/vite.js" ]; then
    echo "error: Wi-Fi Upload dependencies are missing. Run: cd '$root/Web/WiFiUpload' && npm ci" >&2
    exit 1
fi
exec "$node_bin" "$root/Web/WiFiUpload/build.mjs" "$work"
