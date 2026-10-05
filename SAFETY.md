> Version 0.2.0 compatibility update: the exact Mac17,9 backend remains locally tested. Other M1–M5 MacBook Pros use compiled reference-supported recipes after independent identity, fan metadata and required-sensor checks. Earlier Mac17,9-only qualification descriptions below are historical evidence for that recipe, not a restriction on the new registry. See [compatibility](docs/COMPATIBILITY.md) and [distribution](docs/DISTRIBUTION.md).

> Current delivery: [real temperature profiles and measured recovery](docs/TEMPERATURE_PROFILE_STATUS.md). The signed production policy uses a fixed chip envelope and five operational chassis inputs; exact CPU/GPU averages remain estimates, and Top is explicitly proximity.

# Safety

## Current qualification

**All built-in profiles and eligible custom curves are operational on Mac17,9 using the reviewed operational policy.** Both fans passed modest manual targets, watchdog/ownership recovery, helper restart and real Max-to-System operation. Max uses per-fan reported limits and does not need temperature identities. It cannot be used to request lower RPM without qualified chip inputs.

## System and custom ownership

Qualified System restoration revokes the lease before I/O, attempts every fan independently, writes automatic mode 0 only for the verified supported metadata, checks readback, and never clears targets as an unqualified side effect. Firmware mode 3 is neither commanded nor counted as verified automatic ownership. A final pass confirms every fan. Any failure remains **restoration unverified**, never a success-shaped System state. Restoration uses the supported model’s physical IDs independently observed in discovery, separately from RPM/range/count telemetry. Unknown models are refused; no topology is invented. The release path pins the observed lowercase mode keys and cannot fall back to a legacy alias if the real key fails. Retrying does not depend on healthy temperature, actual-RPM or range inputs; broken telemetry must not block a mode-release attempt.

The release codec has now been exercised on this exact Mac17,9 / macOS 27.0 build26A428. It requires lowercase F0md/F1md, ui8 size 1, attribute byte 208, and a current mode of0 or1. An unfamiliar metadata signature or firmware mode 3 is rejected, never guessed around. The report retains initial mode, command success, immediate mode, final mode and each error. Mode0 readback proves the tested ownership handoff; RPM remaining temporarily high does not imply manual control.

No target clearing is implemented. After verified handback Apple independently changed targets to0 and stopped the fans. An already-automatic observation establishes idempotence only. Idle external ownership changes report a conflict rather than starting a write fight; retries remain available after a failed Fandy release.

Custom mode uses manual ownership and temporarily replaces Apple's ordinary demand. A fan floor that reliably preserves higher Apple demand has not been established. Fandy does not fake a floor by multiplying a hidden Apple curve or interpreting actual RPM as Apple demand. The profile floor is a minimum within Fandy's own manual policy. System+/School hand back ownership at idle so Apple's stopped-fan behavior remains available.

## Remembered default and scheduling

The saved default is a profile identifier, never a manual mode, target, lease or heartbeat. Startup first verifies automatic handback, then requires fresh hardware/sensor/helper eligibility before selecting an active schedule or that default. A corrupt configuration blocks automatic default resumption. First launch defaults to System. A scheduled profile does not overwrite the default and returns through System when its occurrence ends. Temporary timers and process watches do not persist, and faults block automatic default retries until a deliberate selection. Selecting System supersedes the current scheduled occurrence.

## Failures and lifecycle

| Event | Required behavior / current verification |
| --- | --- |
| Normal Quit | Request immediate automatic restoration, then terminate. Model tested; physical active-Max and variable-speed termination passed native diagnostics. |
| GUI crash, SIGKILL, frozen controller | Ten-second heartbeat expires; helper restores, checked every 100 ms. Physical heartbeat expiry and SIGKILL of the signed controller passed both-fan handback; coordinator tests also use a virtual clock. |
| XPC disconnect | Revoke that connection's lease and restore; no other connection can renew it. Coordinator tested; physical owned disconnect passed both-fan handback. |
| Helper crash/restart | launchd KeepAlive restarts it; startup revokes all state and restores. No stale target/lease is read from disk. Restart model tested; live helper SIGKILL/startup recovery passed during modest manual ownership. |
| Helper hung/SIGSTOP or blocked kernel I/O | No userspace timer can guarantee restoration while the helper cannot execute. This residual failure is explicit and is not covered by the GUI heartbeat. |
| Missing, corrupt, non-finite or stale required sensor | Relinquish control; never substitute zero. Both processes validate independently. Sequence/time advancement is checked; a constant temperature is not falsely classified as broken. |
| Sensor recovery | Stay in System. A deliberate profile selection and five healthy acquisitions are needed. |
| RPM transaction failure | Attempt automatic restoration on all fans, including a fan whose write may have partially applied. Never claim the profile is active. |
| Rapid profile switching / invalid edit | Generations and lifecycle tokens discard old success/failure acknowledgements and in-flight readings after backend changes, profile switching, sleep/wake or quit; invalid drafts preserve the previous validated profile. |
| Sleep | GUI resets selection; root helper separately receives IOPM will-sleep, revokes and restores before acknowledging. |
| Wake | Helper restores again. GUI starts System and reacquires sensors. Runtime manual intent is cancelled. Eligible configured schedules may activate only after fresh checks; saved manual selections never resume. Actual sleep/wake test pending. |
| Logout/reboot/shutdown | No deliberate persistence of manual fan state. launchd startup assumes restoration, not old demand. An unscheduled reboot cannot provide a guaranteed userspace cleanup opportunity. |
| Profile corruption | Preserve original bytes, salvage individually valid records, restore all built-ins, start System. |
| Severe thermal pressure | ProcessInfo serious/critical/unknown causes restoration to Apple. No invented hardware critical threshold. |

The helper also independently increases fans if its chip guard requires more cooling while a valid lease exists. In 0.2.4 nominal-pressure guard demand below 75°C is time-averaged over at most three seconds to reduce brief acoustic surges; sustained demand reaches its full value within that window. At 75°C and above or fair pressure, raw guard demand is enforced immediately. This timing is compiled into the helper and cannot be extended by profile settings or IPC. Missing history uses the current raw value. The full chip guard remains active when CPU or GPU is deselected in a profile. At 85°C the current guard requests each fan's reported maximum. This is a conservative application policy, not a claim about Apple's shutdown/throttling thresholds. Fandy changes no power limits, clocks, system thermal services or emergency keys.

The OS/firmware's precise behavior under custom manual mode, sleep, reboot and helper failure is undocumented and not proved here. The app does not depend on presumed independent hardware protection to excuse weak watchdog behavior.

## Hardware gates

The historical [bounded recovery qualification path](docs/MANUAL_QUALIFICATION.md) used helper-derived targets, an initial five-second deadline, fifteen-second recovery deadlines and a ten-second heartbeat. Subsequent variable-speed qualification passed the full controller recovery cases before production curve authority was enabled. Its former deadline authority is disabled in production. The current batch sequence verifies both manual modes before validated targets; automatic target preloading failed on this model and is not a fallback path.

Repeated automatic restoration, modest manual testing, watchdog recovery, helper restart, System/Max and temperature-profile activation have passed. Sensor qualification covers the operational inputs actually used by each policy. Competing controllers must not issue fan writes. TG Pro's privileged helper was stopped for these tests; its displayed System setting alone did not establish exclusive ownership. Reference recordings remain development evidence. No maximum-RPM first test, target clearing, Ftst experiment or die-target/system-service changes were made. See [hardware gates](docs/HARDWARE_GATES.md).

Five-minute sequential ordinary-use comparisons in System, System+ and Cool Chassis passed with stable demand. Defaults still require subjective typing-comfort/noise feedback and actual gaming observations; the comparison started cooler than the supplied comfort baseline. The comfortable baseline is Trackpad ≈27°C, Actuator ≈25°C, Airflow ≈33°C; the warmer observation is ≈31°C/29°C/43–44°C. Do not promise exact temperatures or performance preservation under arbitrary load/ambient conditions.

## Historical class-time development boundary

Production monitoring is the normal startup path, with automatic release on helper startup, explicit System requests, lifecycle cleanup and failed Fandy restoration. It never issues manual RPM. Simulation is explicit. At that stage, every requested sensor role, including proximity roles, was required before manual tests or profiles. The subsequently approved bounded mechanical-test exception and revised policy-specific delivery plan are recorded below. Sensor failure cannot block the qualified mode-release path. The user ended the class-time restriction and authorized the physical restoration and bounded measurements documented above.

## Earlier mechanical results

Both fans accepted 2517 RPM and spun up in a five-second mechanical test, then returned to automatic0. The failure was premature acknowledgement checking: early target reads could return0 after an accepted write. The helper now permits up to 500 ms of bounded read-only acknowledgement without a rewrite or deadline extension. Changed nonzero targets, mode/bounds faults, persistent zero and expiry still abort and restore.

Actual heartbeat expiry 10.0293 s, owned disconnect 1.2152 s, fixed deadline 15.0064 s and signed controller SIGKILL passed both-fan handback; independent readings saw manual then automatic modes. Helper death/restart passed during an owned modest trial; physical sleep/wake remains untested. No Max, target clearing, power changes or emergency thermal-service changes occurred.

The user shortened the delivery plan: sensors are to be qualified by the policy that uses them, rather than all twelve blocking every feature. The former maximumControl stage admitted System/Max first. The current qualifiedControl stage also enables curves using the explicit chip-envelope and chassis-proxy policy; unresolved physical CPU/GPU identities were not relabelled as proven.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.

## Production Max acceptance

Both reported maxima were 7826 RPM in this test, and manual readings reached approximately 7815 / 7780 RPM before verified System handback. Limits are freshly read separately. Production controller SIGKILL and heartbeat expiry passed both-fan release; the active termination diagnostic exercises normal cleanup. Target/mode acknowledgement alone did not count as physical Max proof: the fixed check observes RPM for eight seconds. A commanded fan still stopped/below its spinning minimum after ten seconds triggers restoration, without allowing heartbeats to hide a stalled fan.

Sensor-free leases admit only exact maximum targets. The helper still requires fresh valid fan telemetry, supported modes/metadata, unchanged bounds and nominal/fair pressure. The temporary own-helper kill action was removed after restart acceptance. A blocked/dead helper remains unable to run its timer; one successful launchd recovery is evidence for the tested case, not a universal guarantee.

## Production temperature integration

The helper computes a fresh independent chip guard from the complete fixed 105-key envelope. Each required member must be typed, plausible and freshly acquired; no estimate/partial group substitutes on failure. Top proximity remains a mandatory airflow-group input with its uncertainty disclosed. Profile and helper escalation targets round upward to whole RPM within each fan's verified integral limits, and acknowledgement tracking uses normalized values. Invalid normalization restores both fans. Curves themselves retain continuous interpolation.

The reviewed transaction establishes both manual modes before writing validated targets. It never clears automatic targets or tries alternate keys. Every admitted update refreshes the SMC target. Client-side reuse is limited to an immediately issued (250ms) observation; the helper independently reacquires before writes and retains its message limits. Normal startup/wake remains System-first. The former fifteen-second qualification authority is disabled in production; heartbeat and stall recovery remain active.

Actual variable-speed heartbeat, disconnect, bounded deadline, controller SIGKILL and normal quit passed. Live profile activation, rapid switching and handback passed. Earlier helper-restart evidence remains applicable because startup restoration is unchanged. A dead or blocked helper cannot run its watchdog; active physical sleep/wake still needs an observed test.

## Timer versus acquisition timing

Expiry and restoration retries are evaluated on the existing 100-ms helper timer. Full sensor, ownership, conflict and stall observations are paced at two per second during a lease; GUI status and target transactions still independently sample. Independent thermal escalation therefore occurs on the next scheduled acquisition, with I/O/scheduling latency, while heartbeat expiry is not delayed by that sampling budget. Canonical expiry checks run again after hardware calls return. Idle monitoring read errors never schedule unowned fan writes; failed Fandy handbacks remain pending and retry. Physical active sleep/wake still requires a coordinated manual wake and is not represented as passed by model tests. See [measured results](docs/ARCHITECTURE_SECURITY_PERFORMANCE_REVIEW.md).

## Editor/persistence improvements and current evidence

Valid live edits remain independent of disk acknowledgement; invalid drafts/imports never activate. Startup, login and wake remain System-first, regardless of stored selection. Quit requests automatic release before waiting for profile persistence. Diagnostic file buffering cannot delay control or grow without bound. No watchdog deadline, sampling rate, required sensor membership or reviewed SMC command sequence was relaxed by this cycle.

Exclusive thirty-minute System and Cool Chassis controller sessions completed with both fans independently verified automatic afterward. Late real chip-envelope heating triggered maximum cooling through the existing guard; no stimulus was generated. Physical active sleep/wake remains untested pending coordinated wake, and a dead/blocked helper still cannot execute its watchdog. See [delivery results and measurement limits](docs/IMPROVEMENT_DELIVERY.md).

## Timer/schedule behavior — 2026-10-03

Manual menu selections outrank schedules. Timed/process-bound intent expires toward System, followed by fresh admission of an eligible current schedule. Sleep, restart and backend changes discard runtime intent. Schedules are user-configured fresh policy, not recovered manual RPM state. The existing engine's fan/sensor gates, immutable guard, authenticated leases and helper heartbeat remain unchanged. A failed active occurrence is blocked from automatic retry.

Expiry checks run before/after acquisition and before dispatch, but ordinary timer precision includes polling/I/O latency. The helper heartbeat remains the independent crash/freeze fallback, with its documented ten-second timeout and dead/blocked-helper limitation. No new privileged deadline or command is introduced. Native import replacement cancels control intent; portable files cannot qualify another model. Raw display readings never become control inputs. See [timing limits and actual results](docs/SCHEDULING_DELIVERY.md).

## Recovery presentation and activation defaults

An actual verified handback clears a retained unverified-restoration fault; failure stays visible and continues retrying. Startup explicitly requests qualified System restoration before monitoring. Immediate menu checkmarks represent user selection, with pending control shown as Starting/Restoring. Timing conditions can be attached before acknowledgement without bypassing fresh input/lease gates. Per-profile durations/application conditions apply to manual activations, never resume from disk and never override scheduled ranges. A missing configured application blocks manual activation. Universal configuration undo never resurrects a runtime manual lease.


An optional temperature goal adds cooling demand and cannot reduce curves, floor or immutable chip safety. It uses the same fresh/qualified input requirements; target-sensor failure returns to System. It is not a precision thermostat or a guaranteed achievable temperature. Response bands are profile-control choices, not asserted Apple critical thresholds.

## Legacy force-test interfaces

Ftst transfers normal thermal-controller ownership; it is not an Apple-supported safety API. Acquire is bounded to seven seconds with cancellation, fresh sensor/guard and metadata checks. Every release attempts all fans, clears/readbacks Ftst, then independently reads all modes. Partial fan failure cannot suppress global release; global failure prevents a verified System claim. Lost handover is not reasserted. Mode 3 is recognized only by reviewed reference recipes; the tested Mac17,9 recipe is unchanged. No Apple emergency or helper-death recovery guarantee is asserted. A dead or blocked helper cannot execute its watchdog; restart restores before sensor discovery if launchd and hardware I/O cooperate.

## Installing updates

Downloads do not interrupt cooling. Normal update installation stops pending controller work, verifies automatic restoration independently of temperatures, persists configuration and unregisters the old helper. A failed handback or service removal prevents Fandy from consenting to replacement. Startup refuses control from a helper with a stale build identity and performs a bounded service refresh under Apple control. New macOS approval may be required.

Force-killing Fandy bypasses its normal quit gate. Sparkle may finish a previously staged install after process death; helper watchdog/restart recovery remains the protection in that case. A dead or blocked helper cannot execute its watchdog, and app updating does not eliminate that limitation.
