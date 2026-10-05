# Architecture review — 2026-10-05

The connection-cancellation, persistence, application-tracking and scheduling changes pass review. No blocking safety or maintainability issue was found in the changed paths.

## Reviewed boundaries

- **Cancellation:** typed, process-local tokens carry global and per-connection epochs. Connection admission is bounded to eight peers. Rejection revokes that peer's work; disconnect immediately invalidates its queued and running tokens. System and power transitions still cancel every peer. Tokens are not supplied through XPC. Watchdog transactions carry their lease owner; automatic restoration does not depend on a live token or temperature readings.
- **Helper:** authenticated five-method XPC, serial hardware ownership, independent restoration and the existing command sequences remain intact. No new hardware authority, arbitrary key, target or filesystem operation was introduced.
- **Persistence:** the actor advances its revision fence even when unchanged definitions do not need another write. Only successfully written configurations are acknowledged; failed writes invalidate the cache and permit same-revision retry. Remembered defaults remain part of the saved configuration. Runtime selections do not save an active lease.
- **Imports:** legacy profile imports now share the bounded depth and nested-field validation used by configuration and scheduled-profile imports. Imported data cannot grant hardware qualification.
- **Application tracking:** activation and expiry reuse a validated catalog snapshot. Exact PID/start-time liveness is still checked before retaining an application condition, so a cached exited process cannot keep a profile active.
- **Schedules:** lookahead intersects each weekly interval with each calendar day. Overnight tails, Sunday-to-Monday wrapping, query endpoints and matching pauses are covered.

The changes reduce duplicate work and consolidate validation without adding unrelated abstractions. Helper state remains owned by one serial queue; the small ingress fence uses an explicit lock. Review cleanup removes an unreachable switch default and places a native-view formatter test on the main actor.

## Verification

- 394 Swift tests pass: 53 hardware, 204 core and 137 application tests, with one build job and serial test execution.
- 48 tool tests pass.
- Nine focused Thread Sanitizer tests pass, covering connection cancellation, global cancellation, bounded admission, concurrent cancellation, protected handover, persistence failures and catalog reuse. No sanitizer race was reported.
- The final full Swift run has no compiler warnings.
- All fan transactions in this review use mocks or injected transports. No physical fan writes, helper replacement or changes to user configuration were performed.

Software coverage does not prove physical recovery on every supported Mac. In particular, a dead or blocked helper cannot execute its watchdog. Existing live recovery evidence is retained; the newly scoped cancellation path has not been retested through physical controller termination in this review. Other-Mac physical compatibility, actual sleep/wake and subjective calibration retain their previously documented limits.

## Build and packaging

Release 0.2.0 build 10 succeeds. The final arm64 app and its embedded helper retain their matching identifiers and signing team. Both the app and DMG are Developer ID-signed, accepted by Apple notarization and stapled. Gatekeeper app/image assessments, mounted payload verification, privacy checks and image integrity pass. Xcode emits only its informational App Intents metadata-extraction notice because this app does not use that framework.

The local artifact is `build/Distribution-Architecture-0.2.0-build10/Fandy-0.2.0-arm64.dmg`; its checksum and verification report remain local. SHA-256: `2ccebe9d9c3d3adabf22271e9a6dec3d74703a5622d272e438d21e3df127d198`.

This delivery builds and packages the reviewed sources; it does not install them or replace the public GitHub release.
