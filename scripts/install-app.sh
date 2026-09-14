#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
cd "$repo_root"
source_bundle="$repo_root/build/PaneGrid.app"
destination=/Applications/PaneGrid.app
if [[ ! -d "$source_bundle" ]]; then /bin/zsh "$repo_root/scripts/build-app.sh"; fi
[[ -w /Applications ]] || { printf '%s\n' '/Applications is not writable. Ask an administrator to copy build/PaneGrid.app there using Finder.' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$source_bundle"
if [[ -e "$destination" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
  [[ "$existing_id" == dev.panegrid.app ]] || { printf '%s\n' 'Refusing to overwrite an unrelated application.' >&2; exit 1; }
fi

# JXA invokes zero-argument Objective-C selectors on property access; calling the resulting Bool throws.
# Request an orderly quit without Apple Events or privileged commands.
/usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("dev.panegrid.app"); for (var i = 0; i < apps.count; i++) { void apps.objectAtIndex(i).terminate; }'
stage_dir="$(/usr/bin/mktemp -d /Applications/.PaneGrid-install.XXXXXX)"
/usr/bin/ditto "$source_bundle" "$stage_dir/PaneGrid.app"
/usr/bin/codesign --verify --deep --strict "$stage_dir/PaneGrid.app"
running_count="$(/usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSRunningApplication.runningApplicationsWithBundleIdentifier("dev.panegrid.app").count;')"
if [[ "$running_count" != 0 ]]; then
  printf '%s\n' 'PaneGrid is still running, possibly finishing an arrangement. Nothing was replaced; quit it and retry.' >&2
  exit 1
fi
if [[ -e "$destination" ]]; then /bin/mv "$destination" "$stage_dir/Previous-PaneGrid.app"; fi
/bin/mv "$stage_dir/PaneGrid.app" "$destination"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination"
printf '\nInstalled for all users: %s\n' "$destination"
printf '%s\n' 'Each user must grant their own Accessibility permission. No permissions or login items were changed.'
if [[ "${1:-}" != --no-open ]]; then /usr/bin/open "$destination"; fi
