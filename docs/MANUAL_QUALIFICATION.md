# Bounded fan qualification

## Separate authorities

The signed model registry now has `recoveryQualification` authority for user-approved, finite mechanical recovery trials before complete sensor identity qualification. It cannot admit ordinary profile leases. `canControl` still requires all twelve verified sensor roles and physical manual/recovery proof; none of those identities has been promoted. The original all-sensors `ManualQualificationPlan` / `ManualQualificationSession` remain separate pure models.

The authenticated `qualifyRecovery` XPC method accepts only version 2, a fixed `initial` / `recovery` / `heartbeat` action, and a session UUID for heartbeat. Unknown fields, arbitrary RPM, fan IDs, keys, durations or trust switches are rejected. The helper computes targets, samples temperatures itself and owns all deadlines. There is one initial trial and at most eight recovery trials per helper process; longer recovery requests require a completed initial activation and verified both-fan handback, so a failed initial attempt cannot unlock them; restart discards state and restores automatic mode first.

## Admission and transaction order

Automatic restoration must already be qualified on the exact model/topology and succeed freshly before admission. Each acquisition must be fresh (at most two seconds), finite and advancing; every requested candidate reading must be present and healthy or explicitly unverified. Nominal/fair pressure and a diagnostic peak below75°C are required. A wider dynamically enumerated Tp/Tm/Tg domain supplements candidate readings during these bounded tests. Prefix membership establishes no sensor identity or complete safety coverage, and75°C is a measurement ceiling, not an Apple critical temperature.

Targets are `max(fresh actual RPM, reported minimum) +200`, independently within each fan's freshly read bounds. Reported minima/maxima are treated as application constraints, not claims of firmware enforcement. No Max or downward experiment is admitted.

A stopped-fan exception is explicit: both actual speeds and stale targets must be zero, and the diagnostic peak must be below60°C before each activation. This uses the reviewed M5 mode-first sequence, one fan at a time: verify exact mode/target metadata, write mode1, verify a fresh manual/zero-target baseline, write minimum+200, then verify target and mode. It never applies to a spinning fan or nonzero stale target. Any failure immediately releases both fans. The current local reported minimum2317 gives a2517 RPM request; neither constant is embedded in the policy.

A spinning baseline still requires preparing and verifying both targets under automatic mode before either manual write. Failed preloading never switches to the stopped sequence. On this machine an accepted automatic preload read back zero, so spinning qualification is currently blocked by that sequence. No target clearing or unlock key is implemented.

Every physical qualification write now queries and verifies size, type and attribute metadata on the same IOKit connection immediately before its byte-write command. The fixed80-byte selector2 codec validates command results and response lengths; data types are encoded from exact reviewed metadata. Per-fan root methods recheck the model and absolute deadline before and after I/O. No generic physical setManual/setTarget implementation is exposed.

## Revocation and evidence

The initial deadline is five seconds from admission, including activation. Recovery deadlines are fifteen seconds; heartbeat expiry is ten seconds. Neither status nor heartbeat moves the hard deadline. A100ms helper timer checks fresh data, ownership, target, bounds and clock. Disconnect, owned malformed requests, invalid/stale readings, thermal uncertainty, power events and partial writes revoke and request automatic restoration of both fans. A different connection cannot renew the owner. Late client replies cannot revive cancelled diagnostics.

Reports retain baseline/targets, command-stage timestamps and readbacks, the first handback report, the latest restoration report, reason, failure and restoration time. First manual-to-automatic evidence survives later idempotent requests. Independent programmatic fan reads are required for physical acceptance; RPM alone never proves ownership.

A dead, suspended or blocked helper cannot execute its timer. Deadline checks resume after blocking I/O returns; they do not guarantee a hard real-time limit or cleanup during helper failure. Launchd restart recovery remains an unproved live gate.

## Actual result and next step

Three instrumented attempts did not spin either fan. Automatic preload was accepted but read back zero; stopped mode-first reached mode1 on fan0 but target still read zero, including with the type field populated. Each aborted immediately and returned both fans to verified mode0. These are failed activation attempts, not a passed five-second trial. The first restoration report now preserves partial manual ownership.

A same-connection metadata query/write correction passed injected tests and signed compilation, but its physical retry is pending exclusive ownership: TG Pro's privileged helper remains running after its GUI was closed. Automatic approval review blocked the next trial until that competing helper is safely stopped. The machine remains automatic.

Next: establish exclusive ownership, retry the single bounded initial test, then independently verify deadline, heartbeat expiry, disconnect and signed-controller SIGKILL. Helper restart, malformed owned requests, sensor failure/staleness, normal quit, rapid switching and sleep/wake remain before general profiles. All requested sensor identities and chip coverage remain mandatory for production control and calibration.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.
