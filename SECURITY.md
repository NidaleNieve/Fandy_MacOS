# Security

## Privilege and installation

Sensor/key/fan metadata reading worked from the ordinary user discovery process on this Mac. Fan-mode/target writes are confined to a root helper because writable SMC access is privileged on the researched implementations. Local privilege requirements and write behavior must still be confirmed in the hardware gates; the GUI is never run as root.

SMAppService registers the signed launch daemon from the application's bundle. Its plist is `Contents/Library/LaunchDaemons/is.dsr.fandy.fan-helper.plist`; its executable is `Contents/Library/HelperTools/FandyFanHelper`; its fixed Mach service and bundle identifier are `is.dsr.fandy.fan-helper`. This modern bundle-based mechanism does not copy files into `/Library/PrivilegedHelperTools` through a custom installer. No installer shell, legacy privileged generic command runner or kernel component exists.

The user-approved restoration-first build is registered through SMAppService. Its compiled authority permits reviewed automatic-mode writes and a distinct bounded mechanical-test sequence on Mac17,9; ordinary lease/target methods remain rejected even with authenticated callers. Sensor qualification cannot be bypassed by preferences, IPC, launch arguments or helper reports. First launch still acquires no manual lease. App and helper retain the exact Team and identifiers. The older observation service was unregistered before replacement; bundles are preserved while registered.

## Exact XPC interface

| Method | Accepted data | Purpose |
| --- | --- | --- |
| status | No arguments | Bounded versioned status with independently sampled sensors/fans and fresh observed ownership. Wire version 2 includes observationOnly and optional informational capability/per-fan and retained startup restoration reports. Never renews heartbeat. |
| beginLease | Version, UInt64 generation, enumerated required sensor roles | Creates one connection-owned expiring UUID lease after valid hardware/sensors. |
| applyTargets | Version, lease UUID, generation, recent helper snapshot UUID, complete fan-ID/RPM list | Validates again inside helper, enforces chip guard, applies a bounded transaction and renews heartbeat. |
| restoreAutomatic | No arguments | Revoke/release ordinary and recovery ownership, verify every fan; reserved admission capacity. |
| qualifyRecovery | Version2, fixed initial/recovery/heartbeat action, heartbeat session UUID | Helper-derived finite mechanical trial; no caller-supplied RPM, IDs, keys, duration or qualification. |

No arbitrary SMC key, command, mode, path, URL, shell, process-launch or file-read/write parameter exists. The release encoder produces only mode0. The separate qualification codec permits exact metadata-scoped mode1 and bounded targets, with same-connection metadata validation and first/later handback reports; firmware mode 3 is unqualified and cannot be written. No networking, Keychain operations, camera, microphone, screen access, Accessibility, Full Disk Access or user-document access exists in the helper. Reading its own code-signing identity uses Security.framework, not a Keychain entitlement or arbitrary identity lookup.

The separate `recoveryQualification` compiled authority permits only user-approved finite mechanical trials before sensor identity completion. One initial5-second trial and at most eight15-second recovery trials per helper process are admitted, with a10-second heartbeat timeout and nonrenewable deadlines. Every candidate reading must be present/fresh/finite; a wider raw diagnostic domain supplements it without qualifying identities. The stopped-fan path requires both speeds and old targets0 and a below60°C diagnostic peak before each activation. A spinning baseline must successfully preload targets in automatic mode; failures never switch sequences. Restart restores before diagnostics initialize. No preference, payload or received capability report can grant this authority. The all-sensors `manualQualification` model and ordinary control gate remain distinct.

## Peer authentication

The listener uses the public macOS 13+ `NSXPCListener.setConnectionCodeSigningRequirement`. It accepts only `anchor apple generic`, its own signing Team ID and exact `is.dsr.fandy` identifier. The client uses `NSXPCConnection.setCodeSigningRequirement` with the same Team ID and exact helper identifier. No PID-only trust, private audit-token KVC or unrestricted same-team check is used. The framework's requirement enforcement authenticates connecting code before messages are dispatched. Ordinary root-origin connections are additionally rejected; the intended GUI is unprivileged.

A genuine signed app from another user can request safe release, but a UUID lease is owned by one connection and cannot be renewed by another. An already authenticated compromised GUI can request fans within policy bounds; this is the deliberately granted capability. Helper-side sensor sampling, immutable chip guard and expiry restrict that capability.

JSON input is capped at 16 KiB before queueing, versioned and decoded into fixed types. Unknown roles, negative/overflowing unsigned generations, malformed numeric values and non-finite floats are rejected. IDs must exactly cover actual enumerated fans with no duplicates; targets must be within each fan's own valid finite bounds. Snapshots must have been issued recently by this helper. All transactions validate before writes and restore on partial failure. A token bucket permits a burst of ten messages and four/sec afterwards, checked before serial-queue admission.

Admission is bounded to eight connections, four outstanding ordinary requests globally, and two per connection. Automatic restoration has separate capacity: one outstanding request per connection and eight globally, independent of ordinary traffic and token budgets. Duplicate pending releases receive an explicit error; the app shares overlapping lifecycle releases through one RPC. Successful release is never cached for later requests. Rejection notifications coalesce to one per connection, with eight globally, so rejected traffic cannot itself build an unlimited safety-queue backlog. Disconnect immediately invalidates queued tickets and schedules exactly one owned-lease cleanup; closed connections retain their slot until that cleanup runs. These bounds reduce queue starvation; they do not make blocked hardware I/O interruptible. An arbitrary unsigned process cannot access the interface.

The helper has one serial queue for XPC, watchdog and power events. No filesystem lease, profile deserialization or user-configured trust policy exists in the root process. In-memory state is discarded on process restart. Blocked I/O remains an explicit watchdog limitation.

## Uninstall

Before unregistering, release and verify automatic ownership. The implemented user-process `HelperManager.uninstall(client:)` performs that sequence then calls `SMAppService.unregister()`. The normal control uninstall UI will be exposed with live qualification. The separate fixed observation diagnostic can unregister a confirmed read-only helper or an approval-pending service; it cannot unregister a control-capable helper without the qualified release path. Never unload/delete a helper while it owns a manual lease. If restoration cannot be confirmed, use a validated existing controller's System mode and inspect fan modes before removing the service. Profiles/logs can then be removed from the user's Application Support/Fandy directory; this requires no privileged helper operation.

## Review status

Software tests cover authorization requirement construction, injection rejection, bounded malformed messages, hostile fan IDs, NaN/Infinity, lease identity/generation, stale snapshots, flooding, partial hardware failures and watchdog release. Code-signature acceptance/rejection is checked on actual built artifacts. Actual observation-only Mach service connections, ad-hoc/wrong-ID rejection, genuine reconnect and old-helper unregister/new-helper register were tested. Physical failure behavior and live manual watchdog recovery remain pending hardware gates. No source review substitutes for these tests. See [review notes](docs/SECURITY_REVIEW.md).

## Production preparation review (2026-10-01)

Local capabilities are compiled into the signed model registry. Neither deserializing a helper status nor changing Simulation can grant hardware authority. Every requested sensor role is required before ordinary manual qualification or custom profiles; the explicit finite mechanical-test exception qualifies no identities; release is temperature-independent under the approved restoration-first gate; unsupported hardware fails closed. The coordinator now receives capabilities directly, without an independent boolean that can accidentally authorize writes.

The automatic-only codec accepts a validated physical fan ID and matching lowercase mode metadata, with exact type/length and known mode checks. It emits one fixed 80-byte command and validates output length and SMC result. It cannot encode RPM targets, manual mode, arbitrary keys or target clearing. The production transport is confined to the root helper. The new fixed qualification method exposes no user-selectable hardware argument; its separate codec cannot be reached through ordinary profile messages. Tests inject an inert transport; the production release path separately passed both-fan handback and60-second independent observation.

Status reports distinguish observed ownership from sensor eligibility. Per-fan restoration failures remain failures even if a later mode read looks automatic. Existing native authentication tests remain applicable; live manual recovery remains unproved. The approved observation and restoration services were replaced by the signed bounded-qualification build through normal SMAppService unregistration/registration.

## Mechanical qualification review

Injected transport tests verify key-info query9 then byte-write6 on the same connection, exact key/type/size/attribute checks, Float encoding, bounds, mode/target baselines and firmware/response failures. Generic physical setManual/setTarget still throw. The root process accepts no arbitrary key, duration, file, shell, URL, PID or process-launch command.

After TG Pro's helper was stopped, bounded read-only acknowledgement established that early zero target reads were stale. A modest five-second trial, heartbeat expiry, disconnect, fixed deadline and signed controller SIGKILL all passed both-fan mode handback. Unknown nonzero targets and readback expiry still fail. No arbitrary method or permission was added for this fix. A dead/blocked helper still cannot execute its timer; launchd recovery remains unproved.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.
