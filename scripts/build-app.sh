#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
cd "$repo_root"
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
  printf '%s\n' 'Usage: /bin/zsh scripts/build-app.sh [release|debug]' >&2
  exit 2
fi

/usr/bin/xcrun swift build -c "$configuration" --product PaneGrid
/usr/bin/xcrun swift build -c "$configuration" --product PaneGridFixture
binary_dir="$(/usr/bin/xcrun swift build -c "$configuration" --show-bin-path)"
/bin/mkdir -p "$repo_root/build"
stage_dir="$(/usr/bin/mktemp -d "$repo_root/build/.bundle-stage.XXXXXX")"
app_bundle="$stage_dir/PaneGrid.app"
helper_bundle="$app_bundle/Contents/Resources/PaneGrid Practice.app"
/bin/mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$helper_bundle/Contents/MacOS" "$helper_bundle/Contents/Resources"
/bin/cp "$repo_root/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
/bin/cp "$repo_root/Resources/Fixture-Info.plist" "$helper_bundle/Contents/Info.plist"
/bin/cp "$binary_dir/PaneGrid" "$app_bundle/Contents/MacOS/PaneGrid"
/bin/cp "$binary_dir/PaneGridFixture" "$helper_bundle/Contents/MacOS/PaneGridFixture"
/usr/bin/xcrun swift "$repo_root/scripts/MakeIcon.swift" "$stage_dir/PaneGrid.iconset"
/usr/bin/iconutil -c icns "$stage_dir/PaneGrid.iconset" -o "$app_bundle/Contents/Resources/PaneGrid.icns"
/bin/cp "$app_bundle/Contents/Resources/PaneGrid.icns" "$helper_bundle/Contents/Resources/PaneGrid.icns"
if [[ -f "$repo_root/LICENSE" ]]; then /bin/cp "$repo_root/LICENSE" "$app_bundle/Contents/Resources/LICENSE"; fi

# Optional: choose an existing local identity. No key, account, or .env file is required.
signing_identity="${PANEGRID_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --options runtime --timestamp=none --sign "$signing_identity" "$helper_bundle"
/usr/bin/codesign --force --options runtime --timestamp=none --sign "$signing_identity" "$app_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
/usr/bin/plutil -lint "$app_bundle/Contents/Info.plist"

destination="$repo_root/build/PaneGrid.app"
if [[ -e "$destination" ]]; then
  previous_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
  [[ "$previous_id" == dev.panegrid.app ]] || { printf '%s\n' 'Refusing to replace an unrelated bundle.' >&2; exit 1; }
  /bin/mv "$destination" "$stage_dir/Previous-PaneGrid.app"
fi
/bin/mv "$app_bundle" "$destination"
printf '\nBuilt: %s\nSigning: %s\n' "$destination" "$signing_identity"
printf '%s\n' 'Local signing is not Apple notarization. See README before distributing binaries.'
