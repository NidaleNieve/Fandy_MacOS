# Remembered profiles and native helper setup — 2026-10-04

Version 0.2.0 build 4 implements a persistent everyday profile, separate from temporary automation and physical ownership.

## Behavior

- Ordinary profile selections become the remembered default. Reopening verifies System handback, fresh readings, hardware capability and helper health before resuming an eligible active schedule or that default.
- Weekly occurrences temporarily replace the default. Their end and gaps return through System to the default. A manual selection during an occurrence supersedes that occurrence; future periods may still run.
- Until Changed is a reversible checkmark. When enabled it pins a runtime override against schedules; disabling it lets weekly automation run again.
- Duration and application-close overrides remain temporary. Adding a timer to a newly selected profile retains the preceding default. Their expiry returns through System to the schedule/default. No timer, PID, lease or RPM survives restart.
- Corrupt data, unavailable inputs and control faults cannot manufacture a successful activation. Faults and sleep cancel runtime overrides and block automatic default resumption until deliberate selection. Wake remains System-first; existing eligible schedule behavior is retained.
- Removing a default custom profile resets the preference to System. Async collection/import publication preserves newer user selections and queues persistence of the merged preference. Global settings exports include the default identifier; older files decode it as System.

## Helper approval

Fandy uses a signed privileged background helper, not a system extension. On supported hardware, normal startup registers the bundled SMAppService daemon through the existing installation/signing checks. Missing approval disables non-System profiles and adds red status indicators in the native menu, Profiles and Settings. System release remains available. A direct Open System Settings action uses Apple's Login Items entry point; a nonblocking native setup sheet explains approval. Normal fan eligibility remains distinct from registration status. Diagnostics and tests do not register services through this path.

## Verification

- 359 Swift tests pass: 48 hardware, 191 core, 120 app. The eleven added tests cover saved-default restart, scheduled gaps/end, active-schedule restart, explicit System during a schedule, reversible Until Changed, temporary activation, sensor-failure/deletion behavior, permission presentation and portable preference validation. Two reproduced save races are also covered: reselecting an already-active profile during duplication, and retrying failed configuration storage after a new default selection. Both now retain the identifier in memory and on disk. Existing concurrency tests assert remembered selections survive asynchronous imports/deletions.
- 46 Python tool tests pass.
- [GitHub Actions run 37211826964](https://github.com/NidaleNieve/Fandy_MacOS/actions/runs/37211826964) passes all four jobs for delivered code commit 9505d05: software tests, sanitizers, native Release compilation on macOS 15 and macOS latest. These compile/test checks do not substitute for other-Mac physical testing.
- One-job signed arm64 Release build passes; deployment minimum remains macOS 15. App/helper identifiers and private signing configuration are unchanged.
- Installed update followed verified automatic restoration, normal GUI termination, verified unregistration, complete signed-bundle replacement and native reregistration. Helper/login registration remained enabled. Personal profile files were preserved; the existing Cool Chassis selection was migrated privately into the new preference before the normal app reopened.
- The temporary-store live startup check passed five ticks: System, helper controlReady, modes 0/0, no monitoring warning.
- Two normal launches produced fresh Cool Chassis records. Between them normal Quit retained the preference and independent mode observations verified automatic handback on both fans. The delivered app remains running Cool Chassis. The initial low-demand records were automatic. A subsequent independent final observation confirmed both modes 1 while Cool Chassis demanded cooling. This is ordinary operation, not a new manual-control qualification.
- Permission-denied presentation is covered by injected registration-status/model/native-menu tests. This already-approved machine was not deliberately deauthorized. Native layout and actual approval dialogs remain subject to human review; no screenshots or GUI automation were used.

## Package

`build/Distribution/Default-Profile-Final-0.2.0-build4/Fandy-0.2.0-arm64-Test.dmg`

SHA-256: `e65d260c0d3a78b7ea357250d789542ff0dd5f4da718ce1c20e1a23ff5f26cd2`.

The mounted image contains only Fandy.app and an Applications shortcut. Required license notices remain inside the signed bundle. App/helper signatures, matching identity, hardened runtime, arm64 architecture, payload privacy, image integrity and read-only mounted contents pass. No personal settings, local diagnostics or signing configuration are packaged. This is an Apple Development-signed, unnotarized test image. Developer ID signing/notarization remains a distribution prerequisite; do not describe the image as Gatekeeper-ready.

## Remaining limits

Other Apple Silicon notebook compatibility remains reference-supported rather than physically tested. Actual sleep/wake, subjective chassis comfort and sustained gaming calibration remain the previously documented follow-ups. A dead/blocked helper cannot run a watchdog. This change does not alter the privileged API, SMC transactions, hardware authority or recovery qualification.
