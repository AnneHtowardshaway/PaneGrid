# Contributing to PaneGrid

Use the installed Xcode toolchain and Swift Package Manager. The core module is deliberately independent of AppKit window control so geometry and validation can be exhaustively tested.

## Before proposing a change

1. Run `swift test` and inspect the actual XCTest counts and exit status.
2. Build with `/bin/zsh scripts/build-app.sh`.
3. Run `.build/debug/PaneGrid --verify-interface /tmp/PaneGrid-interface.json` in a logged-in macOS desktop session.
4. For window-control changes, install the build, approve Accessibility yourself, then run `/bin/zsh scripts/verify-native.sh`.
5. Test the real UI with the included practice windows. Check the quick picker, drag spans, selected-only reflow, empty slots, failure messages, and undo.

Never treat exit 77, missing permissions, skipped assertions, a zero-test summary, or a successful build alone as a passed native test. When fixing a regression, verify that the test also detects the original defective behavior.

## Safety rules

- Use public macOS APIs only. Do not patch other applications or system preferences.
- Never work around or programmatically grant privacy/security approval.
- Keep AX messaging bounded and off the main thread.
- Use stable live AX references for movement; never select a target by title alone.
- Keep imported JSON bounded and validated. Preserve malformed local files before replacing anything.
- Refuse ambiguous saved-window matching. Empty space is better than moving the wrong document.
- Verify actual frames and complete rollback state; do not equate a setter's return code with successful positioning.
- UI tests and automation must target practice windows, not personal documents.

## Screenshots and sharing

UI changes should include real runtime screenshots in `docs/pr-assets/<change>/`, with a dedicated screenshots section in the pull request. Cover distinct states; bug fixes should include before/after evidence when practical. Capture only the relevant app window. Do not publish screenshots with private document names, account details, signing identities, or unrelated windows.

Do not commit build outputs, local configuration exports, certificates, credentials, or machine-specific paths. Publishing source does not require Apple distribution credentials. Distributing compiled binaries is a separate signing/notarization task.
