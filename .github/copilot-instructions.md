# PaneGrid development

## Project checklist
- [x] Requirements: original, offline, native macOS window manager; no proprietary branding or assets.
- [x] Scaffold: Swift Package Manager, separate core/app/fixture/test targets.
- [x] Implement grid picker, layout editor, persistence, settings, and safe native window control.
- [x] Extensions: none required; use the installed Xcode toolchain.
- [x] Compile and test the core, then build the native app.
- [x] Create and run a VS Code build task.
- [x] Install and launch the locally signed application in /Applications.
- [x] Finish live UI and Accessibility window-control verification after macOS approval: 24 native checks and 53 UI/safety/artifact checks passed.
- [x] Complete README, license, privacy, screenshots, and release instructions.
- [x] Fix consecutive sixths/eighths rollback (1.1.1): prove native red → green, serialize latest pending commands, and require explicit fitting alternatives.
- [x] Install 1.1.2: separate size/position corrections, add red-to-green axis tests, make entire window cards selectable, remove Place, and auto-place on Apply.
- [x] Install 1.1.3: prove enhanced-AX Code edge failure red→green with actual presentation bounds, serialize axis completion, add bounded cancellation and mixed-entry tests, label all presets by dimensions, and verify green-button hold plus native short click.
- [ ] Test with a physically attached second display before claiming that hardware configuration is verified.

## Rules
- Use only public macOS APIs. Do not change system tiling preferences, bypass Accessibility consent, or read the TCC database.
- Keep grid/packing/serialization logic in PaneGridCore and test edge cases before native integration.
- All window operations must target explicit, live AX elements. Never target windows by title alone.
- Check actual frames after resizing. Roll back a failed arrangement rather than leave overlapping windows.
- Do not repeatedly restart an accepted asynchronous resize or infer a minimum from an unchanged old frame. Test successive presets on the same windows without Undo/reset between commands.
- If size already matches, repair only position. Move before growing at a screen edge; never equate equal printed sizes with an equal full frame.
- Enhanced AX may report a logical destination before the on-screen animation finishes. Confirm uniquely associated public WindowServer geometry before starting the next axis; CG metadata is observation-only and must never replace the explicit live AX write target. Test Workspace → app-wide picker → Workspace on the same windows.
- Preserve normal short-click green-button behavior when adding hold recognition. Intercept only recently verified external button bounds, revalidate before opening, and replay non-hold clicks without recursion.
- A preset is exact. Offer a fitting alternative only after a measured refusal, and never apply it or overwrite the chosen grid without explicit acceptance.
- Never resize unselected windows. Keep absent saved-window matches empty, and preserve gaps.
- Keep UI on the main actor and potentially blocking AX messages on the serial accessibility queue.
- The app has no network service, telemetry, account, API key, or third-party package dependencies.
- Do not include personal window titles, device identifiers, signing identities, or local paths in committed screenshots/logs.
- Build and test from this repository root. Generated binaries belong in ignored build directories.
- Release archives for other machines require a distributor's signing and notarization; local ad-hoc signing is not notarization.
