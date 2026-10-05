> 0.2.0 update: [compatibility release results](COMPATIBILITY_RELEASE_VERIFICATION.md). Existing Mac17,9 physical evidence remains; other M1–M5 notebook recipes are reference-supported with runtime checks and synthetic transport coverage. New live M5 profile/quit/disconnect/heartbeat/controller-kill regressions pass. Legacy Ftst physical recovery is not asserted, and the current root-helper kill retest/physical sleep-wake remain pending.

# Hardware qualification gates

Current signed authority is model-specific `qualifiedControl`: real monitoring, automatic restoration, fixed Max and real temperature profiles using the reviewed chip-envelope/comfort policy. Arbitrary sensor-free RPM, independent manual-mode primitives, automatic target clearing and unknown modes remain unavailable. Preferences and XPC payloads cannot grant authority.

| Gate | Actual state |
| --- | --- |
| Research / licensing / pure models / UI | Implemented; real monitoring is default and simulation is explicit. |
| All requested sensor roles and coverage | Identity/coverage evidence remains pending. The revised roadmap qualifies sensors by policy requirements; production gating is now policy-specific. Mechanical tests qualify no mappings. |
| Automatic restoration | Both mode1→0 transitions, three idempotent requests and 60 seconds of independent mode observations previously passed. |
| First modest manual trial | Passed: a single 2517 RPM request per fan, observed spin-up, five-second expiry and both mode1→0 handbacks. Bounded acknowledgement fixed premature readback. |
| Exact write sequence | Same-connection metadata/write and bounded readback passed injected tests and physical modest trials. |
| Live watchdog / disconnect / SIGKILL | Passed live heartbeat expiry, disconnect, fixed deadline and signed controller SIGKILL with independent mode reads. |
| Helper restart / malformed inputs / sensor faults / quit / switching / sleep | Live helper SIGKILL/restart handback passed. Physical sleep/wake remains pending. Dead/blocked-helper limitation remains explicit. |
| Real profiles / calibration | System+, Gaming, Cool Chassis, School and custom curves passed actual app-model activation, independent RPM/mode checks and System handback. Ordinary-use comparisons are recorded in delivery status; subjective/game calibration remains separate. |

## Release requirements

Restoration is temperature-independent and restricted to reviewed model IDs0/1 and canonical lowercase mode metadata. It records initial mode, command result, immediate and later readbacks, attempts the other fan on partial failure, and fails overall if either is unverified. Never infer ownership from RPM or clear targets as an undocumented side effect. Mode3 or changed metadata is rejected.

Competing controllers must be stopped before qualification; no automatic-write fight is allowed. TG Pro's closed GUI previously left its root helper running and a trial was blocked. The user then stopped that service; absence was verified before the successful tests above. No running Macs Fan Control or ThermalForge controller/helper was identified. Installed applications alone do not establish active ownership.

## Bounded trial requirements

See [the exact qualification protocol](MANUAL_QUALIFICATION.md). Helper-derived targets stay upward and within separately read fan bounds. Historical mechanical qualification admitted stopped/zero-target mode-first control. Production curve qualification subsequently established that automatic preloading does not persist on this model. Reviewed batch activation now verifies both manual modes before validated target writes, with upward-only bounded trials from stopped and spinning automatic baselines. No sequence fallback, Max-first, downward cooling test, Ftst, thermal-daemon manipulation or caller-selected target is permitted.

Initial expiry is five seconds; recovery expiry is fifteen seconds regardless of heartbeat, or ten seconds without heartbeat. Restore and independently verify both fans after every attempt. Status retains the first handback evidence separately from later releases. A timer cannot run while the helper is dead or blocked; actual restart behavior must be measured honestly.

After first activation works, prove each recovery case with independent mode/RPM logs. Any unreliable release blocks general control. Startup/wake remain System-first. Sensor qualification must record provenance, type, timing, alternatives and uncertainty; temperature resemblance alone cannot pass a role.

No screenshots, Computer Use or GUI automation. Raw reference CSV, recordings, operator details and signing configuration stay outside public Git. Preserve the registered bundle and unregister through verified release before replacement.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.

## Earlier Max acceptance — 2026-10-01

The app-model Max diagnostic observed actual RPM near each reported maximum, then verified both modes 0 after System. Production Max lease SIGKILL and heartbeat expiry passed with independent mode observations and both initial-mode-1 restoration reports. Normal termination is exercised directly from active Max by a fixed native diagnostic. 157 Swift tests and signed native build pass. The helper self-kill diagnostic was temporary and removed; the dead/blocked-helper limitation remains documented.

## Temperature-profile acceptance — 2026-10-02

The signed `qualifiedControl` build enables every temperature profile with six reviewed operational inputs. CPU/GPU display identity claims remain pending; Top is labelled proximity. Ordinary live profile tests passed: System+/School acknowledged automatic-at-idle, Gaming reached its spinning minimum, Cool Chassis approximately 3420 RPM and a custom curve approximately 2595 RPM. Rapid switching and System handback passed.

Variable-speed qualification observed actual RPM during warm re-entry, target updates and both-fan release. Heartbeat expiry 10.51s, disconnect 1.04s, fixed deadline 15.14s, controller SIGKILL recovery 0.17s, and active normal termination passed. The first eight-second warm observation was too short: positive RPM appeared around nine seconds. Production retains its ten-second stalled-fan check. Whole-RPM upward normalization fixes fractional target acknowledgement and applies to independent helper escalation.

189 Swift tests, 31 Python tests, signed single-job build and strict deep signature verification pass. Helper replacement used verified release/unregister/absence/register. Actual active sleep/wake remains pending; startup/wake reset is implemented and tested in models. A dead or blocked helper cannot run its watchdog. Raw recordings and signing configuration remain private.

## Native-polish regression

200 Swift tests and 31 tool tests pass after editor/status improvements. Signed single-job compilation, strict deep signature verification and the refreshed real-profile diagnostic passed, including invalid-draft retention/correction and active numerical editing. System-first startup and independent both-fan automatic observations passed. This pass changed no hardware transaction or authority; earlier recovery evidence is retained, and physical sleep/wake remains unobserved.

## Refreshed production recovery and performance

The architecture/security pass retains production eligibility, command construction and batch order. Post-I/O expiry checks and a separate 2-Hz acquisition budget preserve the 100-ms expiry/release cadence. Final modest spinning-fan trials passed controller SIGKILL (~0.032s), heartbeat (~10.057s), disconnect (~0.268s) and normal termination (~0.017s), independently verifying both modes. Signed production hostile-input/identity checks and 221 Swift/31 tool tests pass, with sanitizer coverage. Previous helper-restart evidence remains; physical active sleep/wake is prepared but pending a coordinated manual wake. [Detailed scope and results](ARCHITECTURE_SECURITY_PERFORMANCE_REVIEW.md).

## Balanced-polish verification — 2026-10-03

All eligible production profiles remain enabled on the qualified model. The sequential live profile/editor/backend/rapid-switch regression passed. A final bounded heartbeat trial observed rotating manual fans return to automatic after approximately 10.19 seconds. Exclusive thirty-minute System/Cool Chassis sessions maintained policy and fresh inputs and ended in independently verified modes 0/0. Initial overlapping diagnostics and an intentionally stopped power-harness setup are explicitly excluded from acceptance.

These results do not certify physical sleep/wake, editor-open energy use, subjective comfort or sustained gaming. Active full-control-tick p95 was 358.29 ms; short acquisition/status/engine budgets separately passed. See [full results and limitations](IMPROVEMENT_DELIVERY.md). No arbitrary RPM, target-clearing operation or new privileged method was added.

## 0.2.4 fan-response regression

425 Swift tests and 52 tool tests pass; the signed single-job Release build, app/DMG notarization, stapling and Gatekeeper checks pass. Helper replacement verified both-fan automatic release before unregister/register and healthy build-19 startup. A five-minute School-only ordinary-use observation passed, followed by independent automatic modes 0/0. Response and selected chip inputs changed; the physical transaction and restoration recipes did not. Existing hostile-input, watchdog and lifecycle tests remain passing. No synthetic workload, new mode write recipe or broad hardware qualification was performed. See [timing policy, measured results and limitations](FAN_RESPONSE_024.md).
