> Latest checkpoint: [chip-envelope integration](CHIP_ENVELOPE.md), 2026-10-02. The alternative policy is implemented but inactive pending the user's decision and live curve recovery acceptance. Exact CPU/GPU identities and Top semantics remain pending; System/Max remain enabled. A separate bounded render measurement matched fresh reference rows but did not resolve GPU identities.

# Development checkpoint — 2026-10-01

## Working production milestone

**System and Max now work on the real Mac17,9.** The signed app starts in System with real monitoring. Max selects each fan's fresh reported maximum through the same app model used by the menu; System immediately releases both fans to Apple. A checkmark requires acknowledged activation, not a preview. Max needs no temperature identities and activates after one fresh fan acquisition. Curve profiles retain five healthy acquisitions and policy-specific sensor eligibility.

The installed production stage is `maximumControl`. Mechanical transaction/recovery evidence is verified; four comfort roles are reviewed; the remaining chip, Top and proximity records remain pending. This does not block Max. Temperature-based profiles cannot activate yet. Proximity sensors no longer block unrelated policies: `permits(profile)` and the helper's required-role check replace the former all-twelve production switch. No preference or received capability report can grant writes.

The pure production codec and root batch writer are connected and tested. The maximum stage independently rejects every target below the relevant fan's reported maximum. Future curve authority requires a reviewed signed stage and its required verified sensors; no unverified input is promoted by mechanical tests. Low-level independent setManual/setTarget primitives remain unavailable.

## Physical results

| Case | Actual acceptance |
| --- | --- |
| Automatic restoration | Both manual 1 → automatic 0; three repeated requests and 60 seconds independently observed. |
| First modest trial | Both accepted 2517 RPM, computed from reported spinning minimum + 200; actual spin-up and automatic handback at 5.0283 s. |
| Mechanical heartbeat/disconnect/deadline | Both-fan handback at 10.0293 s / 1.2152 s total / 15.0064 s. |
| Signed mechanical controller SIGKILL | Independent reader saw both manual then automatic; helper recorded owned disconnect. |
| Helper SIGKILL/restart | Passed during an owned modest recovery trial. New helper's startup report recorded both initial mode 1, automatic command success and readbacks 0. Independent automatic observation approximately 0.31 s after the fixed restart request. |
| Production Max → System | Both reported limits 7826 RPM; actual manual readings reached approximately 7815 / 7780 RPM before System selection; both automatic afterward. These are observations, not hardcoded limits. |
| Production controller SIGKILL | Passed on the real app-model Max lease; both manual-to-auto reports and independent observations, approximately 0.49 s through observation/status collection. |
| Production heartbeat expiry | Passed without renewal; both manual-to-auto outcomes, physical Max RPM rise and independent automatic readbacks. |
| Production normal termination | Passed directly from active production Max; both mode 1 → 0, with positive RPM near maximum before termination. |

The first three-second Max observation proved target/mode acceptance but ended before tachometer spin-up. It was not counted as physical Max proof. The corrected eight-second diagnostic requires actual RPM reaching at least 90% of reported maximum on both fans. The measured modest trials showed roughly 3.7 seconds before first positive RPM readings.

Accepted target writes can initially read back zero. Bounded read-only acknowledgement (up to 500 ms) fixes that error without rewriting or extending a deadline. Changed mode/bounds, unexpected target, persistent zero, bad clock or late I/O fail toward automatic restoration. The production helper also releases if a commanded fan stays stopped/below its spinning minimum after a ten-second startup grace, even while heartbeat continues.

The temporary authenticated own-helper SIGKILL action was removed. The production helper accepts no signal, PID or process-control command. A dead/blocked helper cannot execute a timer; measured launchd startup recovery does not guarantee recovery from hung kernel I/O. Actual sleep/wake remains untested; its state machine and root power notifications remain implemented and model-tested.

## Verification and installation

169 Swift tests pass (24 hardware, 122 core, 23 app). All 30 Python tool tests pass. Single-job signed native compilation and strict deep signature verification pass. Focused additions cover per-policy capabilities, sensor-free fixed maximum, lower-target rejection, per-fan limits, target ownership, competing controllers, persistent stalled fans, immediate Max, System/wake cleanup and production command encoding.

The preserved signed app is `build/MonitoringDSR/Fandy.app`, registered normally through SMAppService after verified release/unregister and old-service absence. Existing identity `is.dsr.fandy`, helper identity and local signing team remain intact. The final installed build passed a five-tick functional check in real monitoring/System with control-ready helper health and Apple-observed ownership. Authenticated status and three independent fan recordings confirmed automatic mode on both fans. The menu-bar app was then relaunched in System; simulation remains explicit. Raw logs, private signing configuration and the exact local handoff stay ignored by Git.

## Remaining work, in order

1. Resolve CPU/GPU peak membership/coverage using independent current-model provenance or a discriminating source/measurement. Do not repeat idle recordings: the published CPU group may omit the independently observed Tm domain, and one published GPU key is absent. Source tables and rounded temperature agreement are insufficient to settle these conflicts.
2. Review the required chip roles, enable the signed per-policy curve stage, and perform one bounded System+ activation through the already-connected batch writer. Initial activation from a spinning Apple-controlled baseline uses target-first acknowledgement; rejected preload never falls back to an alternative sequence.
3. Finish the remaining Top comfort role, then enable comfort profiles after chip qualification. Trackpad, Actuator and Left/Right are already reviewed. The three proximity roles may remain informational. Curve mapping/source evidence stays explicit; no renamed candidate is treated as proof.
4. Measure actual sleep/wake and rapid production switching. Core lifecycle, race, stale reply, authentication, malformed input and failure tests remain retained; run focused physical regressions when their paths become enabled.
5. Calibrate System/System+/Cool Chassis with human comfort feedback near 27°C Trackpad, 25°C Actuator, 33°C Airflow. Tune gaming separately; no promised exact temperatures, synthetic stress, clock or power changes.
6. Human UI review, release configuration/notarization/distribution and any resulting fixes follow functional completion.

Latest source review checked the current [Stats M5 table](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) and [ThermalForge's exact-model compatibility report](https://github.com/ProducerGuy/ThermalForge/issues/26). The report corroborates Max/Auto operation but does not resolve this machine's chip or comfort identities. No source was copied; existing license notices remain. The original fan/security milestone is now passed for System/Max; the remaining curve blocker is sensor evidence, not an all-twelve prerequisite.

## Resume / reproduce

Read [the latest temperature checkpoint](TEMPERATURE_PROFILE_STATUS.md), this checkpoint, [hardware gates](HARDWARE_GATES.md), [sensor evidence](SENSOR_EVIDENCE.md) and ignored `docs/local/DEVELOPMENT_HANDOFF.md`.

```sh
Scripts/test.sh -j 1 --no-parallel
Scripts/build.sh -jobs 1
```

Never overwrite the registered bundle while its service is enabled. Release/unregister, confirm service absent, replace, verify signature and register. No screenshots, GUI navigation or Computer Use. Fixed production diagnostics require an appropriate noise window; normal operation is local and uses no network.
