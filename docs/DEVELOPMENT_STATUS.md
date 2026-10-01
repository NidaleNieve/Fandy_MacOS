# Development checkpoint — 2026-10-01

## Working state and diagnosed error

The physical writer now works in bounded qualification. Both fans accepted a 2517 RPM target, spun up, and returned from manual1 to automatic0 at the five-second deadline. The target is freshly calculated as each reported spinning minimum + 200; 2517 is a measured result, not a hardcoded policy.

The error was premature target readback. Firmware accepted the write but early observations still returned the old zero target. Fandy aborted a valid asynchronous update after roughly 30 ms. `RecoveryTargetReadback` now observes for at most 500 ms without issuing another command or extending the original trial deadline. It requires unchanged bounds, manual ownership, and the exact target within 0.5 RPM. A nonzero competing target, lost ownership, bad reading, clock fault or timeout still aborts and restores both fans.

TG Pro's privileged helper was stopped by the user and absence was verified. No running Macs Fan Control or ThermalForge utility/helper was identified in process/service checks. Installing those applications alone does not mean they are controlling fans. No other controller was used to produce the passed tests.

Fandy still has its native UI, editable profiles, persistence, real monitoring and shadow calculations. Ordinary real profiles remain disabled; the compiled stage is `recoveryQualification`, not production control. No sensor evidence was falsely promoted to make the tests pass.

## Actual physical verification

Every passed trial verified both fans manual with the requested target, followed by both automatic mode readbacks. RPM alone was not used to claim handback.

| Case | Measured result |
| --- | --- |
| First modest request | Passed; both target 2517 RPM, observed actual peak 2636/2635 RPM during spin-up, both automatic after 5.0283 s. |
| Heartbeat expiry | Passed; controller alive but no heartbeat, both restored after 10.0293 s. |
| Explicit disconnect | Passed; release after 1.2152 s total, about 7 ms after the 1.2082 s disconnect request. |
| Nonrenewable deadline | Passed; heartbeats continued, both restored after 15.0064 s. |
| Signed controller SIGKILL | Passed; diagnostic process exit -9, helper recorded owned disconnect, independent recorder saw manual then automatic on both fans. |
| Helper death/restart under manual control | Not tested. An automatic-only launchctl signal probe was refused by macOS privilege checks; it did not kill the helper. |

A dead, suspended or blocked helper cannot execute its watchdog. KeepAlive/startup restoration are implemented but do not substitute for a measured helper-death recovery test. Physical sleep/wake and the wider failure matrix remain untested; existing model tests are retained.

## Validation and source

**147 Swift tests pass** (18 hardware, 110 core, 19 app), with retained **27 passing Python tool tests**. Single-job signed native build and strict deep signature verification pass. New tests cover delayed acknowledgement, unchanged original deadline, wrong mode/target/bounds, persistent zero and a read completing after the 500 ms acknowledgement window.

Changed source: `SMCRecoveryWriter.swift` adds bounded observation logic; root `FanHardware.swift` uses it after the admitted stopped-mode target write. The endpoint/authentication/RPM calculation do not change. Initial success still cannot be faked by a failed activation. No Max experiment, target clearing, power changes, thermal-service manipulation, screenshot or GUI automation was used.

Raw readings, test process identifiers, reference CSV, operator paths and signing configuration stay outside public Git. The ignored local handoff contains exact artifact locations and reproducible commands.

## Shortened forward plan

The user replaced the earlier all-sensors-first roadmap with incremental delivery. Keep signed authentication, narrow helper methods, bounds/readback, System restoration and watchdog/lifecycle recovery. Defer repeated broad audits, exhaustive sensor qualification and calibration until needed.

1. Prove helper restart recovery from a modest accepted manual target, with independent readings. The previous external launchctl probe lacked OS privilege; choose a narrow test mechanism without adding a generic root command/PID interface. Preserve the residual dead/blocked-helper limitation honestly.
2. Complete production activation plumbing and enable System/Max after the minimum recovery gates pass. Max must remain a fixed maximum request from actual per-fan limits, without requiring all twelve sensor identities.
3. Enable System+ after sufficiently established chip readings. Split eligibility by actual policy requirements rather than the current all-twelve compiled production gate. Do not mark pending identities verified to bypass it.
4. Add Cool Chassis/School incrementally after the comfort inputs they use are established. Proximity sensors may remain informational and must not block every feature. Broader failure checks continue as focused regressions; no repeated general audit.
5. Calibrate comfortable typing with human feedback near 27°C Trackpad / 25°C Actuator / 33°C Airflow, without forcing exact temperatures. Gaming tuning and distribution follow separately.

## Resume

Read this checkpoint, [hardware gates](HARDWARE_GATES.md), [qualification protocol](MANUAL_QUALIFICATION.md) and the ignored `docs/local/DEVELOPMENT_HANDOFF.md`. Production source gates have not yet been changed to the incremental profile policy; all evidence flags remain truthful.

```sh
Scripts/test.sh -j 1 --no-parallel
Scripts/build.sh -jobs 1
```

Do not overwrite the registered `build/MonitoringDSR/Fandy.app`. Release/unregister, verify helper absent, replace the signed bundle and register normally. Fixed recovery diagnostics calculate their own bounded targets. The initial trial is five seconds; recovery trials are fifteen with a ten-second heartbeat timeout and at most eight trials per helper process. Longer trials require successful initial activation and handback. Ordinary menu profiles cannot invoke this test path.
