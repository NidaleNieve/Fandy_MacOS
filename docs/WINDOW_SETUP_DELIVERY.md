# Window, cancellation and setup corrections — 2026-10-04

Version 0.2.0 build 5 fixes the follow-up issues without changing privileged methods or fan transactions.

## Delivered behavior

Profiles uses a dedicated native window, initialized to a 1040×720 content area after its hosting controller is attached. Its SwiftUI controller and hosting view both relinquish intrinsic sizing to AppKit. Content/frame resizing is bounded to at least 960×560 even for programmatic layout changes; native user resizing remains available above the minimum. Root content, profile switches and toolbar changes cannot collapse the window to a transient fitting height.

Ordinary remembered profiles no longer show Cancel. Cancel/Resume appears only for an explicit Until Changed pin, a timer/process condition, an active scheduled period or a paused schedule occurrence. System remains directly selectable regardless of cancellation visibility. The weekly overview leaves unconfigured days empty, retains explicit System schedules when deliberately configured, and lists all configured application-open, application-close and default-duration conditions at the bottom, plus a current temporary override when present. Schedule pauses and overnight continuations remain visible. Unscheduled time uses the remembered default, not a fabricated System schedule.

First-run helper approval uses a dedicated Set Up Fandy window. It does not open Fandy Settings. Guidance names Background App Activity; its button uses the native ServiceManagement System Settings entry point. The nonblocking window polls approval and closes automatically when granted. Later/the close button dismisses it without claiming permission or enabling profiles. Login registration remains automatic on first normal launch because launchAtLogin defaults true; an explicit saved disable preference is respected. Tests/diagnostics do not register services. Existing red indicators and unavailable-profile gating remain intact.

## Validation

365 Swift tests pass: 48 hardware, 191 core, 126 app. Six new cases cover hidden native window creation/layout/content and frame resize bounds, cancellation visibility, empty days versus explicit System schedules, condition projection/order, and dedicated setup approval completion plus login defaults. Paused-occurrence resumption also verifies that the remembered default is never overwritten. Native window tests never show a window or navigate the interface. 46 tool tests and a one-job signed arm64 Release build pass. No screenshots, screen recording or GUI automation were used.

The installed app is replaced only after verified automatic restoration, normal quit and completed helper unregistration. Existing private profiles, signing settings, helper/login approval and the remembered Cool Chassis default are preserved. Runtime startup/reopen observations are recorded locally and summarized in the current checkpoint. Actual unapproved setup appearance remains for human review; this already-approved machine is not deauthorized for UI testing.

## Package

`build/Distribution/Window-Setup-Final-0.2.0-build5/Fandy-0.2.0-arm64-Test.dmg`

SHA-256: `73c5c719fbf92ddab6b6c891a9f8bcbea22daa4bae98b578b4ef123e2f3eec61`.

Signature, identity, hardened runtime, privacy, image integrity and mounted payload checks pass. Contents remain only Fandy.app plus Applications; required license notices remain inside the app. This is development-signed and unnotarized. Developer ID/notarization, physical testing of other Macs, actual sleep/wake and subjective comfort/gaming calibration remain the documented follow-ups.
