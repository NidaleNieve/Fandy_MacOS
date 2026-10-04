# Menu layout and application automation — 2026-10-04

## Delivered

Fandy 0.2.0 build 3 adds a build-generated native fan app icon. The original seven-blade icon uses AppKit paths; generated ICNS files remain build artifacts, with no downloaded artwork, SF Symbol app-icon artwork, raster source assets or runtime dependency.

Every actionable menu row now uses NSMenuItem's native highlight. The hand-painted multiline row was removed. Long titles are bounded with an ellipsis; complete action text remains available through accessibility and tooltips. The main menu has a stable 224-point content width, bounded to 256 points in regression tests. Passive readouts do not contribute changing SwiftUI intrinsic constraints. Activation summaries and observed fan speed are centered.

The Profiles window delegates sizing to the native window/split view, instead of changing SwiftUI ideal widths. Its sidebar remains adjustable and cannot collapse. The window minimum accommodates both columns and the current-status panel. Native scroll indicators are disabled throughout hosted profile content while scrolling remains available. The smaller native segmented selector and wrapping temperature values prevent content from forcing wider columns.

Other Time/Until remains an inline hover submenu. For uses a compact height with centered hour/minute fields. Until uses the clock's native intrinsic size rather than a larger, left-aligned representable frame. Embedded controls resize their height without widening the submenu when changing modes.

**See Schedule** opens a combined seven-day overview from the profile workspace. It includes every enabled profile range, overnight continuations (including Sunday into Monday), and schedule pause ranges. Unscheduled time uses System; the view explains manual/application priority.

**When Activated** now includes “Activate when an application opens”, an application chooser, and “Turn off when this application closes”. The close option shares the existing exact-process activation condition. Without it, the selected duration/until-changed policy applies. Launch rules are included in profile/configuration import/export, duplication and profile Undo/Redo. Old archives decode with launch activation disabled.

The app icon uses original geometry. Apple limits system-provided imagery to interface use and excludes it from app icons in its [Xcode license](https://www.apple.com/legal/sla/docs/xcode.pdf), section 2.10.

## Automation semantics

- Launch detection uses PID plus actual process-start time, not an application name or PID alone. Ordinary polling is bounded to once per second and does not fetch app icons.
- Already-running apps at initialization, wake, configuration replacement or rule edits establish a baseline; they do not re-establish manual fan control.
- Newly observed apps can take priority over a scheduled activation, after a successful monitoring tick and normal profile eligibility checks. An explicit manual selection, including System or a menu timer, suppresses and consumes launch events.
- Multiple simultaneous matches use profile order. Unavailable profiles do not activate; no preference or imported launch rule carries hardware authority.
- Closing a watched process returns through System and then resumes an eligible schedule. Repeated polling does not renew a timer or override a user's replacement duration.
- Applications that open and exit entirely between polls may not trigger; there is no reason to initiate cooling for an already-exited process.

## Verification

- **348 Swift tests** pass with one build job and serial test execution: 48 hardware, 191 core, 109 app.
- **46 tool tests** pass.
- Signed arm64 Release build succeeds with macOS 15 deployment target, existing bundle/helper identities and private signing configuration.
- New tests cover native cancellation/long-name rows, stable menu sizing, compact/resizable embedded controls, native clock size, hosting constraint removal, hidden native indicators, weekly spillover, launch/exit recovery, schedule resumption, timer priority, startup/wake baseline, unavailable activation, Undo/Redo and backward-compatible interchange.
- Update used verified automatic restoration, native helper unregistration, a complete signed-bundle replacement and native registration. Helper and login registration remain enabled; previous bundle is retained in ignored build storage.
- Five live startup ticks pass: System, both fan modes 0, Apple ownership observed, helper controlReady, no monitoring warning. The installed app is running in System.
- Installed icon has a valid ICNS header/length and the app's bundle icon entry points to it.
- No screenshots, screenshot inspection, automated GUI navigation, synthetic loads or manual fan experiments were used for this delivery. Aesthetic judgment remains human review; model/layout tests do not prove visual appearance.

## Artifacts and remaining release work

The refreshed Test DMG and its checksum/verification report are under ignored `build/Distribution/UI-Automation-0.2.0-build3`. Its app is Apple Development-signed; the image is unsigned and neither is notarized. Developer ID Application signing and a private notarytool keychain profile are still required for the broadly shareable release. Existing physical compatibility, helper-death and sleep/wake limitations remain documented in the compatibility/release reports; this UI delivery does not claim new physical verification on other models.
