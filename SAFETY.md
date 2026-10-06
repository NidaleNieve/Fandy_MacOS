# Safety

Current policy: **0.3.1 build 24**. Older measurement reports describe the software tested at their recorded date; the independent temperature-to-fan guard in builds 18/19 is superseded.

## System and custom ownership

System revokes the active lease, attempts automatic restoration on every known fan independently, releases a reviewed force-test handover flag where applicable, and verifies final per-fan modes. Partial failure is reported as unverified restoration. Release does not depend on temperature acquisition. Unknown metadata is rejected; no alternate keys or target clearing are tried.

Custom control replaces normal Apple fan demand. No Apple fan-floor behavior is claimed. A minimum-airflow setting is a floor inside Fandy's own demand calculation, not a way to preserve Apple's higher demand. Each fan uses its own freshly reported RPM bounds.

## Curve-first cooling

Under nominal or fair thermal pressure, requested demand is the maximum of enabled curves, minimum airflow and an optional temperature target. Profile response governs that demand. There is no independent temperature-triggered fan escalation: 75°C and 85°C do not override a profile's configured ceiling. Silent does not receive a hidden maximum-fan request.

All required chip inputs remain mandatory even when CPU or GPU is deselected in the profile editor. Each frozen sensor group must be complete, correctly typed, plausible and freshly acquired. Missing/stale readings, invalid metadata, communication loss or conflicting ownership revoke control and attempt automatic restoration.

Serious, critical or unknown thermal pressure returns ownership directly to macOS, without first issuing a maximum-fan command. The app shows `macOS control — elevated thermal pressure`; it does not automatically reacquire the failed profile while that condition persists. Fandy does not change clocks, power limits or thermal services, cannot command system-wide throttling, and cannot guarantee fanless-MacBook behavior. Apple may independently change fan speed after handback.

## Response and idle

Fan response is 0–100%: Quiet uses fifteen seconds of time-weighted demand averaging and an upward limit of two percentage points/s; Fast uses no averaging and ten points/s. A 20% response uses a twelve-second averaging window. Existing downward hysteresis and rate limiting remain. Max is immediate and uses each fan's reported maximum. Startup and automatic-to-custom entry seed the governor from fresh actual speed, not a stale target. Inherited output is bounded by the next profile's maximum possible configured demand.

Apple auto at idle releases after 15 seconds of zero demand and resumes after demand of at least 5% persists for three seconds. A positive airflow floor prevents that idle release. macOS may run or stop fans while it owns them. Saved curves, automation and idle defaults are not reset by this release.

Surge records preserve up to 30 seconds before and 60 seconds after a ten-percentage-point commanded or observed rise within ten seconds. Records remain local, are limited to 32 events / 8 MiB / seven days, and do not upload automatically. Stronger smoothing cannot guarantee suppression of sustained thermal demand or fan changes while macOS owns the hardware.

## Transactions

All targets and fan metadata are validated before admission. For each automatic fan, the reviewed mode write, narrow mode readback and that fan's target write are adjacent; the next fan is not admitted first. Full readback then verifies target/mode/bounds. Cancellation and deadlines bound direct and reference-supported operations. A partial failure restores every fan. No automatic target preloading or clearing is added.

Fan inertia and firmware can cause actual RPM to differ temporarily from a target. Bounded diagnostics record previous mode/target, actual RPM and mode/target/acknowledgement timing; 20-Hz observations cannot rule out events shorter than 50 ms. An observed transition failure returns to Apple control rather than trying another undocumented command order.

## Process and lifecycle failures

The signed root helper authenticates the genuine application and validates closed XPC messages. A connection-owned lease has a ten-second heartbeat timeout. Disconnect and normal quit release immediately; the 100-ms helper timer checks expiry independently of paced full sensor acquisition. System, quit and sleep revoke in-flight work before release. Actual system sleep suspends monitoring, automation evaluation and periodic updates after restoration. The helper independently rejects new leases while suspended. Wake starts in System; a still-valid override, current schedule or previous ordinary profile can resume only after verified automatic ownership, fresh complete readings and helper readiness. Timers keep their original deadlines; ended application conditions are discarded. Display sleep alone does not suspend Fandy, and Fandy does not prevent or force system sleep. Profile RPM and leases are never persisted across restart; a remembered profile may be admitted only after successful System-first initialization.

The authenticated listener starts before hardware bootstrap. Startup restoration precedes temperature-reader construction and control admission. A failed backend remains connected for structured status and rejects leases. Transient SMC initialization failures have at most three attempts at initial/one/three seconds. Unknown metadata and authentication failures are not automatically retried. Already-automatic reference fans avoid unnecessary protected mode writes, but global release and final ownership verification still run. This is idempotence evidence, not proof of release from manual ownership.

A dead or blocked helper cannot run its watchdog. launchd restart can restore automatic ownership only if launchd, the process and hardware I/O cooperate; no guarantee is made about independent emergency protection during helper death or `Ftst` ownership. The app reports failed restoration honestly.

## Verification limits

Only the M5 Pro Mac17,9 is available for physical testing. Other compiled M1–M5 recipes have source-backed synthetic transport coverage, not physical acceptance. The reported M2 Pro startup problem remains pending friend testing/diagnostics. Real active sleep/wake and sustained gaming calibration remain separate follow-ups. See [build-20 verification](docs/FAN_RESPONSE_024.md), [compatibility](docs/COMPATIBILITY.md) and [hardware gates](docs/HARDWARE_GATES.md).
