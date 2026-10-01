# Safety

## Current qualification

**Automatic restoration is qualified; custom control remains disabled.** The compiled stage is restorationQualification with the observed Mac17,9 fan topology. The user approved restoration before sensor qualification. Both physical fans passed manual mode 1 to automatic mode 0 handback, three repeated release requests and 60 seconds of independent readback on 2026-10-01. Sensor identities/peak coverage and physical manual transactions remain pending. The signed restoration-only helper is registered through SMAppService. Real curve demand is still an inactive preview; simulation is explicit.

## System and custom ownership

Qualified System restoration revokes the lease before I/O, attempts every fan independently, writes automatic mode 0 only for the verified supported metadata, checks readback, and never clears targets as an unqualified side effect. Firmware mode 3 is neither commanded nor counted as verified automatic ownership. A final pass confirms every fan. Any failure remains **restoration unverified**, never a success-shaped System state. Restoration uses the supported model’s physical IDs independently observed in discovery, separately from RPM/range/count telemetry. Unknown models are refused; no topology is invented. The release path pins the observed lowercase mode keys and cannot fall back to a legacy alias if the real key fails. Retrying does not depend on healthy temperature, actual-RPM or range inputs; broken telemetry must not block a mode-release attempt.

The release codec has now been exercised on this exact Mac17,9 / macOS 27.0 build26A428. It requires lowercase F0md/F1md, ui8 size 1, attribute byte 208, and a current mode of0 or1. An unfamiliar metadata signature or firmware mode 3 is rejected, never guessed around. The report retains initial mode, command success, immediate mode, final mode and each error. Mode0 readback proves the tested ownership handoff; RPM remaining temporarily high does not imply manual control.

No target clearing is implemented. After verified handback Apple independently changed targets to0 and stopped the fans. An already-automatic observation establishes idempotence only. Idle external ownership changes report a conflict rather than starting a write fight; retries remain available after a failed Fandy release.

Custom mode uses manual ownership and temporarily replaces Apple's ordinary demand. A fan floor that reliably preserves higher Apple demand has not been established. Fandy does not fake a floor by multiplying a hidden Apple curve or interpreting actual RPM as Apple demand. The profile floor is a minimum within Fandy's own manual policy. System+/School hand back ownership at idle so Apple's stopped-fan behavior remains available.

## Failures and lifecycle

| Event | Required behavior / current verification |
| --- | --- |
| Normal Quit | Request immediate automatic restoration, then terminate. Mock lifecycle/model tested. |
| GUI crash, SIGKILL, frozen controller | Ten-second lease expires; helper restores, checked every 500 ms. Coordinator tests use a virtual clock; live GUI SIGKILL is still a mandatory gate. |
| XPC disconnect | Revoke that connection's lease and restore; no other connection can renew it. Coordinator tested. |
| Helper crash/restart | launchd KeepAlive restarts it; startup revokes all state and restores. No stale target/lease is read from disk. Restart model tested; live launchd restart pending. |
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

The next manual trial has a tested, separate [bounded qualification model](docs/MANUAL_QUALIFICATION.md), currently disconnected from physical writes and XPC. It admits only fully qualified readings, computes exactly +200 RPM per fan, skips stopped/ceiling-limited fans, and has an absolute five-second first-trial deadline. Recovery trials expire after fifteen seconds regardless of heartbeats, or earlier on the ten-second heartbeat timeout. Revocation still needs an executing helper and verified physical restoration; model tests cannot prove that recovery.

Follow [docs/HARDWARE_GATES.md](docs/HARDWARE_GATES.md) in order. Do not grant compiled capabilities merely to make the UI usable. Repeated automatic restoration, all requested sensor qualification, modest manual testing, live watchdog proof and failure tests must precede custom profiles. Competing controllers must not issue fan writes; TG Pro can remain in monitoring/System for the temperature reference while independent mode readings remain automatic. No maximum-RPM first test, no zero target while manual, no Ftst experiment and no die-target/system-service changes.

Defaults still require logged light-workload comparisons in System, System+ and Cool Chassis, subjective typing comfort from the user, and actual gaming observations. The comfortable baseline is Trackpad ≈27°C, Actuator ≈25°C, Airflow ≈33°C; the warmer observation is ≈31°C/29°C/43–44°C. Do not promise exact temperatures or performance preservation under arbitrary load/ambient conditions.

## Class-time development boundary

Production monitoring is the normal startup path, with automatic release on helper startup, explicit System requests, lifecycle cleanup and failed Fandy restoration. It never issues manual RPM. Simulation is explicit. Every requested sensor role, including the three proximity roles, remains required before manual tests or profiles. Sensor failure cannot block the qualified mode-release path. The user ended the class-time restriction and authorized the physical restoration and bounded measurements documented above.
