# Hostile-input review

Reviewed current source, 2026-09-30. This is a scoped engineering review, not an independent audit or completed physical qualification.

| Question | Result |
| --- | --- |
| Can an arbitrary local process connect? | Listener pins Apple chain + exact own Team ID + app identifier through public Foundation requirement enforcement. Actual artifacts accept app/helper requirements and reject wrong ID/team. Live launchd rejects ad-hoc and same-Team/wrong-ID clients; genuine signed status succeeds before/after rejection. |
| Can a caller supply an arbitrary fan ID? | Decode bounded integers; exact complete membership and uniqueness against independent enumeration; rejected before any write. Tested negative, huge, duplicate and absent IDs. |
| Can integer overflow become a fan command? | UInt64 generation decode rejects negative/overflowing JSON; fan IDs stay Int and are range/membership checked before string key formatting. Finite RPM bounds are required. |
| Can a caller request a file, URL, shell or process? | No interface carries those values. Root executable imports no Process/network API and writes no profile/log path. |
| Can malformed values control fans? | Bounded typed decode, fixed roles/version, finite numbers, per-fan ranges, recent helper-issued snapshot IDs and immutable safety demand. Decode failure revokes the owning connection's lease. |
| Can status act as heartbeat? | No. Successful validated target transactions only. A test repeatedly queries status before expiry and verifies release at expiry. |
| Can stale state survive restart? | No persisted lease/target; coordinator starts unverified and restoration is the first action. Observation-only root stop/start through unregister/register tested; restart during a real manual lease remains pending. |
| Can two clients share/steal a lease? | Owner UUID attached to one accepted connection; renew/disconnect validated against that owner. A second genuine connection cannot renew the first lease. Explicit safe-release remains available to authentic clients. |
| Can partial writes masquerade as success? | Failure restores every fan; any failed readback prevents System verification. Spy tests cover first-fan restoration failure and second-fan target failure. |
| Can a caller bypass sensor verification? | Helper independently reads required sensors plus mandatory CPU/GPU guard; caller has no temperature payload or qualification switch. Qualified=false currently refuses leases. |
| Can a helper hang be recovered by its own timer? | No. Serial watchdog cannot execute through a hung I/O call or SIGSTOP. This explicit residual risk must be considered before hardware qualification. |

Observation-only registration is compiled out as soon as either physical qualification becomes true. The observation coordinator rejects begin/apply/release and performs no mutations during startup, watchdog or sleep/wake; tests exercise all these paths. Ownership status is based on fresh typed fan telemetry; a failed read clears previous verified status. On 2026-10-01 live tests accepted the genuine renamed app and rejected ad-hoc and same-Team/wrong-ID callers. Malformed/oversized/unknown-role/overflowing requests, unqualified leases and forged targets were rejected. Read-only release was refused and genuine reconnect succeeded.

Fixed restoration writes exist only in the helper target. Physical manual-mode/target methods currently reject; their implementation must follow the automatic-restoration gate. Restoration uses observed model-specific IDs and exact mode keys, independently of RPM/count telemetry; a failed canonical key never falls back to an unqualified legacy alias. The public CSMC module exports no write function or raw connection port. Temperature-only HID discovery is optional and does not consume input-device events. Normal app diagnostics are fixed-purpose user-space files; root logs use os.Logger.

Observed signing: the locally configured signing Team, app is.dsr.fandy, helper is.dsr.fandy.fan-helper, hardened runtime. Signatures and nested bundle integrity were checked using codesign. Requirement construction tests also reject quotes/path characters to prevent requirement injection. Release qualification requires rechecking entitlements, signatures and exact identities in the installed package; development artifacts do not constitute release validation.

Remaining review work: real launchd/XPC client enforcement and service ownership/approval, practical watchdog scheduling under load, SMC blocked-I/O behavior, current firmware automatic restoration, helper crash/restart, sleep/wake, competing controllers and acoustic/thermal calibration. Do not expose a helper installation button as a workaround for those unresolved gates.

## Mutual identity and callback verification, 2026-10-01

The genuine client additionally pins a deliberately incorrect helper identifier on a separate read-only connection and requires Foundation's exact code-signing-requirement failure (NSXPCConnectionCodeSigningRequirementFailure4102, SDK declaration available macOS13+). A timeout or generic connection error does not pass this test. A genuine status query follows the rejection to establish continued service health. XPC completion/error callbacks are explicitly Sendable and use a locked exactly-once continuation gate; the corrected probe and genuine requirement-failure path exercise background callback delivery.

## Production monitoring review — 2026-10-01

Hardware authority now comes from immutable, model-scoped compiled capabilities and per-role evidence. Observation permits no writes; every requested sensor, topology and physical restoration/manual proof is required before qualified control. A helper status report cannot grant the local app authority. All existing authentication and four-method XPC restrictions remain in effect.

No target-clearing writer remains. The only prepared physical encoder emits automatic mode 0 for canonical, validated lowercase mode metadata; mode 3 is left untouched. It has no RPM/manual/arbitrary-key encoder. The real transport rechecks root UID and compiled authority; inert transport tests verify exact bytes and reject malformed metadata/results. Per-fan restoration attempts remain independent of sensor/RPM telemetry, retain partial failures, and retry rather than hide a failed attempt behind a successful-looking observation.

Preview calculations return a type without targets or leases and do not change original sensor qualification. App lifecycle tokens and XPC transaction tokens prevent obsolete reads/lease replies from reviving a cancelled profile. Normal monitoring quit sends no mutation request. No registered service was replaced or given write authority during this milestone. Live manual-mode failure testing remains required; a hung helper cannot execute its watchdog.

## Restoration-first review — 2026-10-01

The approved stage separates safe release from sensor qualification without widening the four-method XPC interface. Manual/control authorization still requires every requested sensor and physical proofs. Current root methods setManual/setTarget reject every request. The codec produces only automatic0 on canonical lowercase keys with exact ui8/size 1/attributes 208 metadata and current mode 0/1. Mode3 and changed metadata fail closed; target clearing remains absent.

Both-fan manual-to-automatic handback, three repeat requests and60 second independent mode readback passed. Startup results are retained separately from subsequent idempotent requests, without persisted manual state. Reports expose initial/immediate/final modes and partial failures. Genuine status and release succeeded through the existing mutual signing requirements; earlier wrong-ID/ad-hoc rejection remains recorded. Restored mode 0 is not inferred from RPM.

Source review additionally identified an idle external ownership change incorrectly scheduling release retries. Status now invalidates ownership without initiating a write fight. Failed explicit Fandy releases continue retrying. Regression coverage distinguishes these cases. The bounded measurement executable has no XPC/write API and does not ship inside the helper/app. Live recovery from Fandy-owned manual state remains untested because sensor qualification still blocks manual implementation.

## Request admission review

The previous rate limiter ran after serial-queue dispatch. An authenticated caller could therefore enqueue unbounded work before rejection and delay the watchdog. HelperRequestGate now validates payload size and rate before dispatch, bounds connections and outstanding requests, reserves restoration capacity, and coalesces rejection notifications. Closed-peer slots and outstanding ticket counters are tracked independently to cover disconnect/admission scheduling races; queued tickets become inert immediately on invalidation. Eight focused tests cover these limits, malformed sizes, duplicate completion, invalid clocks, disconnect races and reserved release capacity. This is queue containment, not a solution to hung IOKit calls.

The GUI shares overlapping restoration calls without caching success or cancelling the shared release when one waiter is cancelled. Three tests exercise overlapping requests, shared failure/retry and cancellation. Existing authentication, per-fan restoration and all-sensor/manual qualification gates remain unchanged. Physical manual-control and watchdog recovery remain unproved.

The signed restoration-only helper was replaced through normal unregister/register after verified automatic release, with the old bundle backed up privately. Registration remained enabled. Live ad-hoc and same-Team/wrong-ID status clients were rejected; the genuine app's fixed protocol diagnostic passed authenticated status, malformed JSON, oversized input, unknown role, generation overflow, unqualified lease, forged target, reconnection and exact wrong-helper requirement rejection. The real-monitoring functional check passed five acquisitions, System state, Apple-observed ownership and both mode-0 fans. These results cover the current restoration-only service; they do not prove recovery during physical manual control. Verification completed with 111 Swift tests, 27 tool tests and a signed native build.

## Bounded recovery surface — 2026-10-01

The current interface adds one fixed `qualifyRecovery` method under separate compiled recoveryQualification authority. It accepts only version/action/session identity; extra keys, arbitrary RPM/fan/duration/authority and malformed UUID/action combinations fail before activation. Generic lease/apply and physical setManual/setTarget remain unavailable. All sensor evidence remains pending, and no test authority grants ordinary profile control.

The helper derives upward targets within each fresh fan range; stopped admission additionally requires both zero speeds/targets and a diagnostic peak below60°C. Exact mode1/Float commands query verified metadata on the writing connection first. Nonrenewable deadlines start before activation; independent reads recheck deadline/ownership/bounds and reject partial transactions. First restoration evidence survives later releases; another connection cannot renew/reject ownership. Root startup release precedes diagnostic enumeration. No caller path, key, URL, shell, duration, signal or process launch is accepted.

144 retained Swift tests and27 tool tests pass, including metadata/transaction-order, malformed fixed messages, authority separation, deadline/heartbeat, partial activation, sensor/thermal faults and first-handback retention. Physical attempts accepted writes but did not retain targets; fan0 mode1 was promptly released. These failures do not pass live recovery. Automatic approval review blocked the next retry while TG Pro's privileged helper remained active; Fandy verified both fans automatic. The same-connection codec awaits exclusive ownership and live acceptance. Dead/suspended/blocked-helper recovery remains a residual limitation requiring actual restart measurement.

The helper now independently checks for the known TG Pro privileged-controller executable through bounded kernel process metadata enumeration before admission and during a trial. Only a fixed blocker string is exposed over status; no PID/path or arbitrary process operation is accepted. This detects the present conflict, not every possible controller. Continuous fan mode/target checks remain required. Enumeration failure blocks trials; restoration is independent of this guard.
