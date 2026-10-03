> Current delivery: [real temperature profiles and measured recovery](docs/TEMPERATURE_PROFILE_STATUS.md). The signed production policy uses a fixed chip envelope and five operational chassis inputs; exact CPU/GPU averages remain estimates, and Top is explicitly proximity.

# Security

## Privilege and installation

Sensor/key/fan metadata reading worked from the ordinary user discovery process on this Mac. Fan-mode/target writes are confined to a root helper because writable SMC access is privileged on the researched implementations. Physical root-helper transactions and handback have passed on the qualified model; the GUI is never run as root.

SMAppService registers the signed launch daemon from the application's bundle. Its plist is `Contents/Library/LaunchDaemons/is.dsr.fandy.fan-helper.plist`; its executable is `Contents/Library/HelperTools/FandyFanHelper`; its fixed Mach service and bundle identifier are `is.dsr.fandy.fan-helper`. This modern bundle-based mechanism does not copy files into `/Library/PrivilegedHelperTools` through a custom installer. No installer shell, legacy privileged generic command runner or kernel component exists.

The production qualifiedControl build is registered through SMAppService. Its compiled authority permits reviewed automatic release, maximum-only sensor-free leases and qualified temperature-policy leases on Mac17,9. Missing/unqualified required inputs are rejected even from authenticated callers. Sensor qualification cannot be bypassed by preferences, IPC, launch arguments or helper reports. First launch still acquires no manual lease. App and helper retain the exact Team and identifiers. The older observation service was unregistered before replacement; bundles are preserved while registered.

## Exact XPC interface

| Method | Accepted data | Purpose |
| --- | --- | --- |
| status | No arguments | Bounded versioned status with independently sampled sensors/fans and fresh observed ownership. Wire version 2 includes observationOnly and optional informational capability/per-fan and retained startup restoration reports. Never renews heartbeat. |
| beginLease | Version, UInt64 generation, enumerated required sensor roles | Creates one connection-owned expiring UUID lease after valid fan telemetry and policy-required sensors; empty roles designate fixed maximum. |
| applyTargets | Version, lease UUID, generation, recent helper snapshot UUID, complete fan-ID/RPM list | Validates again inside helper, enforces fixed maximum or qualified chip guard, applies a bounded transaction and renews heartbeat. |
| restoreAutomatic | No arguments | Revoke/release ordinary and recovery ownership, verify every fan; reserved admission capacity. |
| qualifyRecovery | Version2, fixed initial/recovery/heartbeat action, heartbeat session UUID | Historical recovery-stage finite trial; disabled in production qualifiedControl. No caller-supplied RPM, IDs, keys, duration or qualification. |

No arbitrary SMC key, command, mode, path, URL, shell, process-launch or file-read/write parameter exists. The release encoder produces only mode0. The separate qualification codec permits exact metadata-scoped mode1 and bounded targets, with same-connection metadata validation and first/later handback reports; firmware mode 3 is unqualified and cannot be written. No networking, Keychain operations, camera, microphone, screen access, Accessibility, Full Disk Access or user-document access exists in the helper. Reading its own code-signing identity uses Security.framework, not a Keychain entitlement or arbitrary identity lookup.

The historical separate `recoveryQualification` compiled authority permitted only user-approved finite mechanical trials before sensor identity completion. One initial5-second trial and at most eight15-second recovery trials per helper process are admitted, with a10-second heartbeat timeout and nonrenewable deadlines. Every candidate reading must be present/fresh/finite; a wider raw diagnostic domain supplements it without qualifying identities. The stopped-fan path requires both speeds and old targets0 and a below60°C diagnostic peak before each activation. That historical spinning trial required automatic target preloading. Current-model curve qualification found preloading ineffective; production uses the separately reviewed mode-first batch sequence below, with no runtime fallback. Restart restores before diagnostics initialize. No preference, payload or received capability report can grant this authority. The all-sensors `manualQualification` model and ordinary control gate remain distinct.

## Peer authentication

The listener uses the public macOS 13+ `NSXPCListener.setConnectionCodeSigningRequirement`. It accepts only `anchor apple generic`, its own signing Team ID and exact `is.dsr.fandy` identifier. The client uses `NSXPCConnection.setCodeSigningRequirement` with the same Team ID and exact helper identifier. No PID-only trust, private audit-token KVC or unrestricted same-team check is used. The framework's requirement enforcement authenticates connecting code before messages are dispatched. Ordinary root-origin connections are additionally rejected; the intended GUI is unprivileged.

A genuine signed app from another user can request safe release, but a UUID lease is owned by one connection and cannot be renewed by another. An already authenticated compromised GUI can request fans within policy bounds; this is the deliberately granted capability. Helper-side sensor sampling, immutable chip guard and expiry restrict that capability.

JSON input is capped at 16 KiB before queueing, versioned and decoded into fixed types. Unknown roles, negative/overflowing unsigned generations, malformed numeric values and non-finite floats are rejected. IDs must exactly cover actual enumerated fans with no duplicates; targets must be within each fan's own valid finite bounds. Snapshots must have been issued recently by this helper. All transactions validate before writes and restore on partial failure. A token bucket permits a burst of ten messages and four/sec afterwards, checked before serial-queue admission.

Admission is bounded to eight connections, four outstanding ordinary requests globally, and two per connection. Automatic restoration has separate capacity: one outstanding request per connection and eight globally, independent of ordinary traffic and token budgets. Duplicate pending releases receive an explicit error; the app shares overlapping lifecycle releases through one RPC. Successful release is never cached for later requests. Rejection notifications coalesce to one per connection, with eight globally, so rejected traffic cannot itself build an unlimited safety-queue backlog. Disconnect immediately invalidates queued tickets and schedules exactly one owned-lease cleanup; closed connections retain their slot until that cleanup runs. These bounds reduce queue starvation; they do not make blocked hardware I/O interruptible. An arbitrary unsigned process cannot access the interface.

The helper has one serial queue for XPC, watchdog and power events. No filesystem lease, profile deserialization or user-configured trust policy exists in the root process. In-memory state is discarded on process restart. Blocked I/O remains an explicit watchdog limitation.

## Uninstall

Before unregistering, release and verify automatic ownership. The implemented user-process `HelperManager.uninstall(client:)` performs that sequence then calls `SMAppService.unregister()`. The fixed signed `--helper-restoration-unregister` diagnostic invokes this release-first path; no arbitrary installer or root file-removal API is exposed. The separate fixed observation diagnostic can unregister a confirmed read-only helper or an approval-pending service; it cannot unregister a control-capable helper without the qualified release path. Never unload/delete a helper while it owns a manual lease. If restoration cannot be confirmed, use a validated existing controller's System mode and inspect fan modes before removing the service. Profiles/logs can then be removed from the user's Application Support/Fandy directory; this requires no privileged helper operation.

## Review status

Software tests cover authorization requirement construction, injection rejection, bounded malformed messages, hostile fan IDs, NaN/Infinity, lease identity/generation, stale snapshots, flooding, partial hardware failures and watchdog release. Code-signature acceptance/rejection is checked on actual built artifacts. Actual observation-only Mach service connections, ad-hoc/wrong-ID rejection, genuine reconnect and old-helper unregister/new-helper register were tested. Modest manual, Max/System, production heartbeat/SIGKILL, normal termination and helper restart recovery have passed; physical sleep/wake and subjective/game calibration remain pending. Real temperature-profile and variable-speed recovery paths passed. No source review substitutes for these tests. See [review notes](docs/SECURITY_REVIEW.md).

## Production preparation review (2026-10-01)

Local capabilities are compiled into the signed model registry. Neither deserializing a helper status nor changing Simulation can grant hardware authority. Production curve policies require their used sensor roles; the disconnected historical manual-qualification model still requires all roles; the explicit finite mechanical-test exception qualifies no identities; release is temperature-independent under the approved restoration-first gate; unsupported hardware fails closed. The coordinator now receives capabilities directly, without an independent boolean that can accidentally authorize writes.

The automatic-only codec accepts a validated physical fan ID and matching lowercase mode metadata, with exact type/length and known mode checks. It emits one fixed 80-byte command and validates output length and SMC result. It cannot encode RPM targets, manual mode, arbitrary keys or target clearing. The production transport is confined to the root helper. The new fixed qualification method exposes no user-selectable hardware argument; its separate codec cannot be reached through ordinary profile messages. Tests inject an inert transport; the production release path separately passed both-fan handback and60-second independent observation.

Status reports distinguish observed ownership from sensor eligibility. Per-fan restoration failures remain failures even if a later mode read looks automatic. Existing native authentication tests remain applicable; live manual/controller recovery has passed for the tested mechanical and production Max paths. The approved observation and restoration services were replaced by the signed bounded-qualification build through normal SMAppService unregistration/registration.

## Historical mechanical qualification review

Injected transport tests verify key-info query9 then byte-write6 on the same connection, exact key/type/size/attribute checks, Float encoding, bounds, mode/target baselines and firmware/response failures. Generic physical setManual/setTarget still throw. The root process accepts no arbitrary key, duration, file, shell, URL, PID or process-launch command.

After TG Pro's helper was stopped, bounded read-only acknowledgement established that early zero target reads were stale. A modest five-second trial, heartbeat expiry, disconnect, fixed deadline and signed controller SIGKILL all passed both-fan mode handback. Unknown nonzero targets and readback expiry still fail. No arbitrary method or permission was added for this fix. A dead/blocked helper still cannot execute its timer; launchd startup handback passed during the owned modest trial; blocked I/O remains a residual limitation.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.

## Production policy admission

An empty required-role lease is maximum-only: every target must equal the fresh maximum of its identified physical fan. Nonempty required roles need the signed qualified curve stage, verified evidence and the immutable chip safety roles. Data received from the GUI cannot change the stage or qualification. The private batch writer validates bounds/metadata again and performs no arbitrary-key operation; independent setManual/setTarget primitives remain unavailable.

The temporary helper restart test could signal only its own process during an authenticated, owned finite recovery session after initial handback. It was removed after successful measurement. Production has no PID, signal, process launch or shell operation. Competing controller/target changes release ownership rather than write-fighting. 189 Swift tests, 31 tool tests, signed native build, actual profile activation and variable-speed recovery support the current checkpoint. Physical active sleep/wake remains unobserved.

## Production temperature integration

The helper computes a fresh independent chip guard from the complete fixed 105-key envelope. Each required member must be typed, plausible and freshly acquired; no estimate/partial group substitutes on failure. Top proximity remains a mandatory airflow-group input with its uncertainty disclosed. Profile and helper escalation targets round upward to whole RPM within each fan's verified integral limits, and acknowledgement tracking uses normalized values. Invalid normalization restores both fans. Curves themselves retain continuous interpolation.

The reviewed transaction establishes both manual modes before writing validated targets. It never clears automatic targets or tries alternate keys. Every admitted update refreshes the SMC target. Client-side reuse is limited to an immediately issued (250ms) observation; the helper independently reacquires before writes and retains its message limits. Normal startup/wake remains System-first. The former fifteen-second qualification authority is disabled in production; heartbeat and stall recovery remain active.

Actual variable-speed heartbeat, disconnect, bounded deadline, controller SIGKILL and normal quit passed. Live profile activation, rapid switching and handback passed. Earlier helper-restart evidence remains applicable because startup restoration is unchanged. A dead or blocked helper cannot run its watchdog; active physical sleep/wake still needs an observed test.

## Refreshed production verification

Lease and target commands now reject unknown/missing top-level fields before typed decoding; response compatibility remains additive. Idle read failure removes ownership evidence without acquiring control. Returning hardware calls are followed by canonical lease-expiry checks. The five-method XPC surface is unchanged. Updated production malformed-request, actual ad-hoc/wrong-identifier rejection, mutual-identity, signature/entitlement and sanitizer results are recorded in [the current review](docs/ARCHITECTURE_SECURITY_PERFORMANCE_REVIEW.md). No source review or sanitizer run proves recovery while the helper is dead or blocked in kernel I/O.

## Profile interchange and local exports

Native file panels are user-initiated operations in the normal GUI process. The helper receives no paths or files. Imported JSON is bounded to one MiB, 128 total stored profiles and 32 nesting levels, validates every profile, rejects authority/reserved identities and assigns fresh custom IDs. Profile-only imports do not select control; user-imported schedules can activate only through normal fresh eligibility. Configuration replacement clears runtime intent and requests System. Diagnostic export is an allowlisted state summary and excludes arbitrary errors, paths, custom names, raw readings and signing identity. CI has read-only repository permissions, contains no signing credentials and runs no hardware actions.

## Automation/import boundary — 2026-10-03

The five-method privileged interface is unchanged. Timers, process enumeration, configuration files and text parsing live in the normal GUI. Process watches compare PID plus kernel start time and treat exited/zombie/reused processes as ended; no arguments or application contents are inspected. No process-list, file, shell or network capability was added to the helper.

Portable formats reject unknown fields, excessive nesting/bytes/items, invalid curves, duplicate IDs, protected-definition changes and unreviewed schedule conflicts. Limits are one MiB, 128 profiles, 1,024 weekly ranges, 256 pauses, 16 readouts and 32 JSON nesting levels. Built-ins retain reviewed identities; custom imports remap IDs. Temporary conditions, live leases, signing metadata and model qualification cannot be imported. Configuration replacement requires a local native confirmation. User-exported names and schedules are private configuration, not part of source publishing.

Launch-at-login preference uses ServiceManagement in the genuine normal app only; diagnostics do not register it. Independent SMC/HID display discovery and raw values are read-only and cannot modify the compiled control policy. See [delivery](docs/SCHEDULING_DELIVERY.md).
