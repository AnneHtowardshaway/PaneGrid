# Verification status

Local development checks on **2026-09-13**, macOS 26.6, Apple silicon, Xcode 26.6 / Swift 6.3.3.

## 1.1.3 — real Code edge-animation failure, cross-entry recovery, and hold

### Actual root-cause evidence

The repeated 1.1.2 failure was reproduced on an explicitly identified **right-edge Code window with enhanced Accessibility enabled**. The original window was 950 points wide at x=2882 on a 3840-point display. Requesting x=2563 and width=1269 through the old transport returned width **958**, exactly the space remaining at its old position, and failed. Merely serializing against AX-reported positions still failed in an intermediate probe (width1251): AX reported a logical destination before the on-screen animation had finished.

The final driver serializes the axes and checks the matching public WindowServer geometry before issuing the next axis. The **same-window old/new comparison** then produced: old algorithm failed at958; new algorithm reached1269×699, remained there after1.3s, and Undo restored the original. Other Code windows were independently checked unchanged. No enhanced-accessibility, native tiling, privacy, or system preference was modified. The CG association is observation-only, requires unambiguous PID+frame, and is never used as a write target; all setters still use the explicit live AX element.

Empty isolated Code instances, even when launched with a renderer accessibility flag, did not reproduce the user's enhanced app-level state and initially passed. Those earlier passes were not treated as proof of a fix. The failing real-edge comparison is the decisive regression evidence (`PaneGrid-live-edge-red-green.json`, machine-local).

### Completed verification

- **43 unit tests** passed, including a regression that proves move/resize axes must not overlap and dimension-preset checks.
- **36 native transition/controller checks** passed, now covering normal, coalesced, and independently animated axes; Workspace→app-wide picker→Workspace without reset; newest pending command; Undo; cancellation, delayed rollback recheck, and arranging again after cancellation.
- **38 general native checks** and **16 interface checks** passed. Existing fit/overlap/rollback safeguards remain in place. All tested stages are bounded; cancellation has its own UI control.
- Installed **1.1.3 (build5)** is signed, matches the tested build byte-for-byte, and initially preserved the configuration file byte-for-byte.
- Real input tests on a temporary practice app verified long-hold opening with hover disabled, release without fullscreen, normal short-click fullscreen, and visible dimension presets including3×3. The picker measured380×586 in single-window mode. Initial preference cleanup missed the async Settings navigation; subsequent actual checkbox action restored hover. No other new user setting was overwritten. A process sample showed the installed app idle/responsive, not deadlocked.

### UI changes

Presets now use dimension labels throughout, including2×1,2×2,3×1,3×2,3×3,4×2,4×3,4×4, and larger. Fourteen presets wrap into three visible rows. Long hold is450ms with live external-button revalidation; short clicks retain their native event sequence. Whole-card selection and no-Place workflow are retained.

Historical screenshots below are not the1.1.3 UI. Multi-display physical hardware verification is still outstanding; no claim is made about every third-party app's size restrictions.

## 1.1.2 — position/size separation and full-card selection

- The user's actual 1.1.1 message reported a failed request even though requested and actual **sizes were both 1269 × 699 pt**. That does not establish a minimum-size refusal: origin/settlement must be checked separately.
- An isolated empty Code process exposed a position-dependent size cap: requesting 1200 × 800 near the bottom first yielded 1200 × 707, even after moving it. A subsequent request away from the edge reached 1200 × 800. The diagnostic confirmed all existing Code window identities and frames were unchanged.
- Three new axis-transport tests failed in six assertions under the original size-then-position sequence. They cover a deferred size update capturing the old origin, bottom-edge growth, and avoiding unnecessary size writes on position-only moves. They pass with `WindowFrameDriver`: move first, request size only if needed, and correct a wrong position without restarting an already-correct resize. Exact full-frame verification and rollback remain enabled.
- **38 unit tests, 38 installed native checks, and 16 installed preset-transition checks passed.** Installed version is 1.1.2; binary comparison, signing verification, and preservation of the settings/layout file were checked. No claim is made that these fixture passes prove every user-window case.
- The window card is now one full-area button with explicit selected/not-selected accessibility state. The separate Place control is removed. Apply packs selected cards automatically; a single selected window can receive a region by grid drag.
- An attempted end-to-end check against the user's current Code workspace stopped at safety gates (the live window set changed, then the expected accessible filtered-card set was unavailable). It did not issue an arrangement. This is **not** counted as a passing live Code regression.

The external UI helper and screenshots below document older UI behavior; their Place-based scenarios must be updated before replaying them against 1.1.2.

## 1.1.1 — consecutive-preset rollback regression

The first-release tests below did **not** cover switching presets on already arranged windows: they generally undid each layout before testing the next. A user's sixths → eighths failure exposed that gap.

### Reproduced before changing production code

- Two new `FrameSettlerTests` failed in **five assertions**. Repeating an accepted request every 280ms restarted a receiver's 550ms resize debounce. The 1.2-second verifier then mistook the unchanged previous size for a minimum size and triggered rollback.
- The same behavior was reproduced on six real, separately launched AppKit windows with a coalescing resize response. **Sixths succeeded; both subsequent eighths commands failed and restored the old arrangement.** Ordinary responsive windows passed. This was an observed native failure, not only a mocked assertion.

### Fix and verified behavior

- Accepted or lost replies now get a read-only response interval before a bounded retry. A minimum-size inference requires an actual change on the relevant size axis; seeing an old layout unchanged is not enough.
- An app-wide preset is exact. The tiler no longer applies a different grid automatically or overwrites the chosen setting. A real refusal produces persistent picker feedback; optional alternatives require explicit acceptance.
- App-wide commands capture immutable target/grid/display/spacing snapshots. Active operations finish or roll back before the newest queued command runs. Superseded pending commands do not run or create undo entries. Incomplete rollback prevents a queued operation from starting.
- Alternative acceptance is bound to the original target and current display geometry, scale, grid, margins, and gaps. Display changes invalidate stale suggestions.

**35 unit tests, 16 native preset-transition checks, 38 general native checks, and 16 actual interface checks passed.** The unchanged failing native sequence became green: sixths → eighths → sixths → eighths all stayed correct after 1.8 seconds. Rapid sixths → twelfths → eighths ended at eighths, with exactly two undo entries (active command plus newest pending command). A genuine 1000pt minimum-width refusal offered an alternate grid without applying it; explicit acceptance and one-step undo both passed.

Machine-local baseline reports: `PaneGrid-preset-red-unit.log` and `PaneGrid-presets-red-native.json`. Passing reports: `PaneGrid-presets-1.1.1.json`, `PaneGrid-native-1.1.1.json`, and `PaneGrid-interface-1.1.1.json`. These test-owned reports are not committed. The installed 1.1.1 executable and signature were checked against the built bundle, and existing configuration was preserved.

## Historical 1.0 verification

The following results describe the earlier release, not substitute coverage for the 1.1.1 regression above.

## Build, core, and native suites

The following suites were run directly before the final external UI pass. The UI-only pass did not rebuild or modify the app:

- **17 XCTest tests passed.** The geometry sweep exercises all 576 column/row dimension combinations from 1 through 24, including bounds and adjacent gaps.
- **13 real-AppKit interface checks passed.** These include dark/light grid sizes, Saved layouts, Settings, the minimum workspace size, and the compact picker budget of 380 × 508 points.
- **24 native cross-process checks passed.** They cover actual fixture frames, unselected-window preservation, undo, selected-group reflow, minimum-size rejection, partial rollback, and the real green-button hit target.
- The earlier sizing regression oracle rejected intrinsic window growth to 1140 × 3037 points; AppKit-owned sizing kept the same views at 1140 × 800 points.

## Visible production UI pass

**53 unique UI, safety, restoration, and artifact checks passed; 0 failed; 0 skipped within the requested run.** Repeated observations are consolidated by check ID. Recovered automation/capture incidents remain separately documented in the machine-local attempts report; they are not represented as production defects or hidden by source changes.

The installed application was exercised externally with the public Accessibility and Core Graphics APIs. Its existing Accessibility access was verified; no permission was requested or changed. No production source, package/configuration file, or app binary was modified. SHA-256 checks matched all **25 protected files**, including both installed executables.

- [x] Resize only PaneGrid's workspace to **1140 × 800 points** and keep it stable.
- [x] Enter the actual **PaneGrid Practice** filter and verify exactly six practice rows before **Select listed**.
- [x] Verify an originally empty draft/group; perform a real **2 × 2 pointer drag**, Place, overlap rejection, and six-window auto-placement while preserving blank cells.
- [x] Activate the real **Apply arrangement** and **Undo** controls; independently measure all six native frames against expected destinations and originals.
- [x] Save and load a uniquely named, practice-only layout. Export and import it through the native file dialogs using a verified temporary file, then remove only the QA layout.
- [x] Navigate Settings and Saved layouts. Change the actual preview checkbox, verify persistence, and restore every original setting.
- [x] Hover the real green button to open **PaneGrid Picker** adjacent to Practice 1; observed opening took approximately **0.62–0.71 seconds**, including polling/AX latency, with the original 0.30-second dwell preference.
- [x] Verify Escape, **Control–Option–Space**, shortcut-toggle dismissal, Workspace's Open picker button, and the picker close button.
- [x] Verify mouse-out with its grace period (**0.859 seconds**) and outside-click dismissal (**0.094 seconds**, before mouse-out could mask a broken click handler).
- [x] Drag a real picker region to resize **Practice 1 only**, verify the other five frames are unchanged, and undo through the production UI.
- [x] Restore the original empty draft/group, single-cell selection, settings, saved layouts, and all six original practice frames. Leave the app open and ready on Workspace, filtered to practice windows, with no selection, assignment, or picker remaining.

No confirmed production bug was reproduced by these checks. This is not a claim that the entire release matrix is complete.

## Native screenshots

All images originate from **single, owner-verified native-window captures**, never desktop captures or reconstructed UI. Workspace/picker crops omit display-identifying controls; standard sRGB encoding removes device-specific color-profile metadata. Crop dimensions and exact normalized-pixel preservation were verified, followed by visual review of the archived files.

| Artifact | PNG dimensions | Captured state |
| --- | --- | --- |
| [Workspace practice layout](pr-assets/first-release/workspace-practice-20260913.png) | 1840 × 1250 | Six practice assignments, including a reserved 2 × 2 span; body crop |
| [Workspace drag](pr-assets/first-release/workspace-drag-20260913.png) | 1840 × 1250 | Actual 2 × 2 selection before assignment; body crop |
| [Settings](pr-assets/first-release/settings-20260913.png) | 2280 × 1600 | Real Settings window with original preferences restored |
| [Picker controls](pr-assets/first-release/picker-controls-20260913.png) | 760 × 828 | Real hover-opened picker; header/display-selector area omitted |

Draft screenshots show test-owned demonstration states **before cleanup**, not the final empty draft. Original full captures remain private and outside the repository.

## Additional release coverage

These are outside this UI pass's requested checks, not passing UI claims:

- [ ] Physically attached second display; this Mac had one display. Negative/vertical transforms remain unit-tested only here.
- [ ] Selected-group **reflow enabled** through the picker UI; the existing native engine suite covers reflow, while this pass checked single-target snapping with reflow disabled.
- [ ] Minimum-size refusal/partial rollback triggered through the workspace UI; the existing native engine suite covers those failure paths.

## Reproduce

- Core: `swift test`
- Live interface: `.build/debug/PaneGrid --verify-interface /tmp/PaneGrid-interface.json`
- Installed native engine: `/bin/zsh scripts/verify-native.sh`
- External UI helper: `scripts/verify-ui-interactions.swift`, compiled separately to a temporary executable. Run from the repository root; only the helper is compiled, not the application.

The UI helper has bounded, resumable stages for preflight, filtering, draft actions, layout/dialog actions, Settings, picker actions, cleanup, artifact encoding, and finalization. It refuses to overwrite its original baseline or screenshot evidence. Keep the two exact installed bundles running, inspect sanitized AX diagnostics before resuming a blocked stage, and visually review native captures before archive/finalize stages. It must never target personal applications or substitute guessed coordinates for verified controls.

Machine-local evidence is in `PaneGrid-ui-interactions-20260913.json`, with complete repeated observations in `PaneGrid-ui-interactions-20260913-attempts.json`. Neither report nor the private settings baseline is copied into the repository.

**A blocked/exit-77 report is not a test pass.** Keep release claims aligned with measured reports and native screenshots; do not infer functioning window management from installation, signature verification, or successful setters alone.
