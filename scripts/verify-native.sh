#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
cd "$repo_root"
report_file="${1:-$repo_root/build/native-verification.json}"
app_bundle="${2:-/Applications/PaneGrid.app}"
[[ -x "$app_bundle/Contents/MacOS/PaneGrid" ]] || { printf '%s\n' 'Build and install PaneGrid first.' >&2; exit 1; }
/bin/mkdir -p "${report_file:h}"
exec "$app_bundle/Contents/MacOS/PaneGrid" --verify-native "$report_file"
