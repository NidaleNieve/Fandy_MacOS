> Temperature integration update: [current results and blockers](docs/TEMPERATURE_PROFILE_STATUS.md). Four comfort roles are reviewed. The curve-qualification stage and helper-owned 15-second deadline are implemented/tested but inactive in the delivered maximum-only build.

# Safety

## Current qualification

**System/Max control is qualified on the reviewed Mac17,9; temperature profiles remain pending their required sensor evidence.** Both fans passed modest manual targets, watchdog/ownership recovery, helper restart and real Max-to-System operation. Max uses per-fan reported limits and does not need temperature identities. It cannot be used to request lower RPM without qualified chip inputs.

## System and custom ownership

Qualified System restoration revokes the lease before I/O, attempts every fan independently, writes automatic mode 0 only for the verified supported metadata, checks readback, and never clears targets as an unqualified side effect. Firmware mode 3 is neither commanded nor counted as verified automatic ownership. A final pass confirms every fan. Any failure remains **restoration unverified**, never a success-shaped System state. Restoration uses the supported model’s physical IDs independently observed in discovery, separately from RPM/range/count telemetry. Unknown models are refused; no topology is invented. The release path pins the observed lowercase mode keys and cannot fall back to a legacy alias if the real key fails. Retrying does not depend on healthy temperature, actual-RPM or range inputs; broken telemetry must not block a mode-release attempt.

The release codec has now been exercised on this exact Mac17,9 / macOS 27.0 build26A428. It requires lowercase F0md/F1md, ui8 size 1, attribute byte 208, and a current mode of0 or1. An unfamiliar metadata signature or firmware mode 3 is rejected, never guessed around. The report retains initial mode, command success, immediate mode, final mode and each error. Mode0 readback proves the tested ownership handoff; RPM remaining temporarily high does not imply manual control.

No target clearing is implemented. After verified handback Apple independently changed targets to0 and stopped the fans. An already-automatic observation establishes idempotence only. Idle external ownership changes report a conflict rather than starting a write fight; retries remain available after a failed Fandy release.

Custom mode uses manual ownership and temporarily replaces Apple's ordinary demand. A fan floor that reliably preserves higher Apple demand has not been established. Fandy does not fake a floor by multiplying a hidden Apple curve or interpreting actual RPM as Apple demand. The profile floor is a minimum within Fandy's own manual policy. System+/School hand back ownership at idle so Apple's stopped-fan behavior remains available.

## Failures and lifecycle

| Event | Required behavior / current verification |
| --- | --- |
| Normal Quit | Request immediate automatic restoration, then terminate. Mock lifecycle/model tested; production active-Max termination is checked by the fixed native diagnostic. |
| GUI crash, SIGKILL, frozen controller | Ten-second heartbeat expires; helper restores, checked every 100 ms. Physical heartbeat expiry and SIGKILL of the signed controller passed both-fan handback; coordinator tests also use a virtual clock. |
| XPC disconnect | Revoke that connection's lease and restore; no other connection can renew it. Coordinator tested; physical owned disconnect passed both-fan handback. |
| Helper crash/restart | launchd KeepAlive restarts it; startup revokes all state and restores. No stale target/lease is read from disk. Restart model tested; live helper SIGKILL/startup recovery passed during modest manual ownership. |
| Helper hung/SIGSTOP or blocked kernel I/O | No userspace timer can guarantee restoration while the helper cannot execute. This residual failure is explicit and is not covered by the GUI heartbeat. |
| Missing, corrupt, non-finite or stale required sensor | Relinquish control; never substitute zero. Both processes validate independently. Sequence/time advancement is checked; a constant temperature is not falsely classified as broken. |
| Sensor recovery | Stay in System. A deliberate profile selection and five healthy acquisitions are needed. |
| RPM transaction failure | Attempt automatic restoration on all fans, including a fan whose write may have partially applied. Never claim the profile is active. |
| Rapid profile switching / invalid edit | Generations and lifecycle tokens discard old success/failure acknowledgements and in-flight readings after backend changes, profile switching, sleep/wake or quit; invalid drafts preserve the previous validated profile. |
| Sleep | GUI resets selection; root helper separately receives IOPM will-sleep, revokes and restores before acknowledging. |
| Wake | Helper restores again. GUI starts System and reacquires sensors. No automatic custom resume. Actual sleep/wake test pending. |
| Logout/reboot/shutdown | No deliberate persistence of manual fan state. launchd startup assumes restoration, not old demand. An unscheduled reboot cannot provide a guaranteed userspace cleanup opportunity. |
| Profile corruption | Preserve original bytes, salvage individually valid records, restore all built-ins, start System. |
| Severe thermal pressure | ProcessInfo serious/critical/unknown causes restoration to Apple. No invented hardware critical threshold. |

The helper also independently increases fans if its chip guard requires more cooling while a valid lease exists. At 85°C the current guard requests each fan's reported maximum. This is a conservative application policy, not a claim about Apple's shutdown/throttling thresholds. Fandy changes no power limits, clocks, system thermal services or emergency keys.

The OS/firmware's precise behavior under custom manual mode, sleep, reboot and helper failure is undocumented and not proved here. The app does not depend on presumed independent hardware protection to excuse weak watchdog behavior.

## Hardware gates

A separate [bounded recovery qualification path](docs/MANUAL_QUALIFICATION.md) is connected to authenticated XPC and helper-only writes. Targets are freshly computed per fan and never supplied by the caller. Initial deadline5 seconds; recovery deadline15 seconds; heartbeat10 seconds. Stopped/zero-target/cool admission permits a reviewed mode-first spinning-minimum+200 request. Spinning admission requires verified target-first preloading. Failure never switches order or clears targets; it restores all fans and retains first/later per-fan outcomes. The broader raw diagnostic guard is not sensor identity or complete chip coverage proof. Production eligibility is policy-specific. Max is sensor-free fixed maximum; curves require their actual chip/comfort roles. Proximity identities do not block unrelated policies.

Follow [docs/HARDWARE_GATES.md](docs/HARDWARE_GATES.md) in order. Do not grant compiled capabilities merely to make the UI usable. Repeated automatic restoration, modest manual testing and live controller watchdog proof have passed. Helper restart and production System/Max activation have passed; temperature profiles remain pending their own evidence. Sensor qualification must cover the inputs actually used by each policy under the revised delivery plan. Competing controllers must not issue fan writes. TG Pro's privileged helper is stopped for these tests; its displayed System setting alone previously did not establish exclusive ownership. Reference recordings remain development evidence. No maximum-RPM first test, no zero target while manual, no Ftst experiment and no die-target/system-service changes.

Defaults still require logged light-workload comparisons in System, System+ and Cool Chassis, subjective typing comfort from the user, and actual gaming observations. The comfortable baseline is Trackpad ≈27°C, Actuator ≈25°C, Airflow ≈33°C; the warmer observation is ≈31°C/29°C/43–44°C. Do not promise exact temperatures or performance preservation under arbitrary load/ambient conditions.

## Class-time development boundary

Production monitoring is the normal startup path, with automatic release on helper startup, explicit System requests, lifecycle cleanup and failed Fandy restoration. It never issues manual RPM. Simulation is explicit. At that stage, every requested sensor role, including proximity roles, was required before manual tests or profiles. The subsequently approved bounded mechanical-test exception and revised policy-specific delivery plan are recorded below. Sensor failure cannot block the qualified mode-release path. The user ended the class-time restriction and authorized the physical restoration and bounded measurements documented above.

## Latest physical result

Both fans accepted 2517 RPM and spun up in a five-second mechanical test, then returned to automatic0. The failure was premature acknowledgement checking: early target reads could return0 after an accepted write. The helper now permits up to 500 ms of bounded read-only acknowledgement without a rewrite or deadline extension. Changed nonzero targets, mode/bounds faults, persistent zero and expiry still abort and restore.

Actual heartbeat expiry 10.0293 s, owned disconnect 1.2152 s, fixed deadline 15.0064 s and signed controller SIGKILL passed both-fan handback; independent readings saw manual then automatic modes. Helper death/restart passed during an owned modest trial; physical sleep/wake remains untested. No Max, target clearing, power changes or emergency thermal-service changes occurred.

The user shortened the delivery plan: sensors are to be qualified by the policy that uses them, rather than all twelve blocking every feature. The maximumControl stage now admits real System/Max leases. Curve leases remain disabled; no pending sensor was falsely marked valid.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.

## Production Max acceptance

Both reported maxima were 7826 RPM in this test, and manual readings reached approximately 7815 / 7780 RPM before verified System handback. Limits are freshly read separately. Production controller SIGKILL and heartbeat expiry passed both-fan release; the active termination diagnostic exercises normal cleanup. Target/mode acknowledgement alone did not count as physical Max proof: the fixed check observes RPM for eight seconds. A commanded fan still stopped/below its spinning minimum after ten seconds triggers restoration, without allowing heartbeats to hide a stalled fan.

Sensor-free leases admit only exact maximum targets. The helper still requires fresh valid fan telemetry, supported modes/metadata, unchanged bounds and nominal/fair pressure. The temporary own-helper kill action was removed after restart acceptance. A blocked/dead helper remains unable to run its timer; one successful launchd recovery is evidence for the tested case, not a universal guarantee.
