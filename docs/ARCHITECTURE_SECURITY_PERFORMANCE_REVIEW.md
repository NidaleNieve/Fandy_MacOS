# Architecture, performance and security verification — 2026-10-02

The requested Improve Codebase Architecture and Thermonuclear Code Quality Review were applied to recent production control, ownership, XPC and lifecycle changes. This is an engineering review with measured integration results, not an independent security audit or a claim of complete hardware protection.

## Defects fixed and architecture changes

1. **Idle observation versus physical handback.** An idle telemetry exception previously set the helper's restoration flag, causing subsequent watchdog writes despite no Fandy lease. The GUI's monitoring catch could independently request the same unsolicited release. HelperSafety now models automatic ownership as observed, unverified or restoring; ControlMachine distinguishes observation failure from an actual failed release. Lost reads remove verified display/activation evidence. They do not acquire external ownership. Actual failed Fandy releases still retry. Tests exercise both processes, external manual ownership, recovered reads and failed-release retention.
2. **Deadline checks after hardware calls.** Status, target completion and independent escalation now use one canonical live-lease check after returning from potentially blocking acquisition/normalization/writes. A late read cannot produce a success acknowledgement or start watchdog escalation after expiry. Injected clocks cover heartbeat and fixed qualification deadlines separately. This does not make kernel I/O interruptible or give a dead helper a timer.
3. **One real batch interface.** Removed unused manual/target primitives and the misleading default per-fan mode/target loop from FanHardwareIO. Every adapter must implement the batch transaction. The coordinator spy now matches production's all-modes-before-targets order; second-mode failure verifies that no targets are written and both fans are released. The physical writer and exact SMC bytes/order are unchanged.
4. **Power observer lifetime.** Polling stop/termination removes both native observer tokens. Restart installs one pair and termination cannot restart polling. An injected NotificationCenter test covers start/stop/start, duplicate start, one posted transition and no post-stop/termination transition.
5. **Closed privileged command shapes.** Lease and target commands reject unknown or missing top-level fields before their typed decode. Responses retain additive-field compatibility. Payload limits, authentication, per-fan validation, independent sensor reads and immutable guard remain enforced; no new XPC method or caller authority exists.
6. **Separate timer decisions from expensive sampling.** The 100-ms watchdog retains expiry and restoration decisions. Full sensor/ownership/conflict/stall sampling runs at most twice per second; GUI status and target transactions still independently acquire fresh readings. Tests prove sampling is paced, thermal escalation occurs on the next scheduled sample and heartbeat release is not postponed by the sampling interval.

These changes deepen the ownership, lease, batch-write and lifecycle modules: narrower interfaces, explicit adapter seams, better transition locality and greater leverage from injected failures. No source file approaches 1,000 lines; diagnostic orchestration stays outside views/helper control logic. The architecture report is generated separately in the system temporary directory; personal paths and raw measurements are excluded from publication.

## Software verification

| Check | Result |
| --- | --- |
| Swift suite, one build job and sequential tests | **221 pass: 28 hardware, 150 core, 43 app** |
| Python tool suite | **31 pass** |
| Address Sanitizer, full Swift suite | **221 pass**, memory-access checking; leak detection disabled |
| Thread Sanitizer, selected concurrency tests | **5 pass**: concurrent ingress, observer lifecycle and three shared-release cases |
| Native signed single-job build | **Pass** |
| Strict/deep installed signatures | **Pass** |
| Hardened runtime / sensitive entitlements | **Pass** for app/helper; no entitlement payloads, no debug attachment/network/screen/automation permissions |

The existing source-table unreachable-default warning and Xcode signed-binary/AppIntents metadata messages are not new test failures. No screenshots, Computer Use, automated GUI navigation, synthetic stress, power-preference changes or proprietary mapping extraction were used.

## Live hostile-input checks

Ad-hoc and same-Team/wrong-identifier status probes were rejected (Foundation connection interruption, no status data). Genuine signed status/reconnection succeeded. A deliberately wrong helper requirement produced the expected Foundation signing-requirement rejection; generic timeout was not accepted as proof.

The signed production diagnostic passed authenticated status, malformed JSON, oversized JSON, unknown role, unsigned-generation overflow, wrong version, caller-supplied qualification authority, forged fan/lease/snapshot targets, disabled historical qualification, reconnect and wrong-helper identity checks. All negative payloads are fixed-purpose. None transmits an admissible lease or target. System ownership was independently verified before/after. The hostile-input unit tests additionally cover foreign lease owners, numeric coercion, missing/extra fields and reserved restoration capacity under concurrent admission.

## Performance observations

Before changes, 30 seconds of System monitoring used approximately 1.3% of one CPU core in the GUI and 1.4% in the helper from accumulated CPU time. Median resident memory was approximately 84 MiB / 12 MiB. These are short development-build observations, not energy-impact or long-term benchmarks.

The first active recovery sampling showed median helper CPU around 14.9% of one core. With the full acquisition cadence limited to 2 Hz, a separate 20-second steady modest lease showed about 5.3% sampled CPU and about 12 MiB helper memory. Accumulated CPU over that steady window was about 6.5% of one core; short ps rolling percentages and accumulated CPU measure different windows. The diagnostic GUI used about 87 MiB. Workloads/phase duration differ, so the observations establish reduced polling work rather than a statistically controlled battery-life claim.

Final read-only checks used twenty 1-second-paced samples under Apple automatic ownership:

| Measurement | Median | p95 | Diagnostic p95 budget |
| --- | ---: | ---: | ---: |
| Complete sensor/fan acquisition | 28.97 ms | 31.77 ms | 100 ms |
| Authenticated helper status | 35.75 ms | 38.03 ms | 250 ms |
| Cool Chassis engine evaluation | 0.070 ms | 0.075 ms | 10 ms |

These budgets are engineering checks for this build/model, not Apple thermal thresholds or guarantees under arbitrary system load. No additional thermal/acoustic calibration is inferred.

## Real recovery on the final installed helper

All cases required manual mode and positive RPM on both fans before the recovery trigger. The modest Cool Chassis profile was used; no Max or downward-speed experiment was performed.

| Trigger | Independently observed both-fan automatic handback |
| --- | ---: |
| Controller SIGKILL | Approximately 0.032 s |
| Heartbeat expiry | Approximately 10.057 s |
| Owned XPC disconnect | Approximately 0.268 s |
| Normal termination | Approximately 0.017 s |

The final complete temperature-profile regression also passed System+, Gaming, Cool Chassis, School, custom curves, valid/invalid active editing, simulation round trip, rapid switching and System handback. System-first functional launch passed five real-monitoring ticks with a control-ready helper and both modes automatic. Max was not rerun: its physical writer/order and bounds policy are unchanged and prior acceptance is retained.

These are sampled timings for the tested sessions, not worst-case bounds. Registration replacement used release/unregister, old-service absence, signed replacement and normal registration. Previous actual launchd helper-death/restart evidence is retained; no privileged process-kill operation was reintroduced.

## Explicit remaining checks

- **Physical active sleep/wake is not passed yet.** A fixed 90-second native-notification diagnostic is prepared. It activates a modest profile, requires real will-sleep and did-wake notifications, verifies System-first wake and independently reads both automatic modes. It neither changes power preferences nor requests sleep. Automatic wake scheduling requires administrator authorization unavailable noninteractively here; a human wake must be coordinated before arming it. Model/power-notification tests are not substituted for physical evidence.
- A dead, suspended or kernel-blocked helper cannot run its timer. Post-I/O expiry checks guarantee decisions only when execution resumes; they cannot interrupt a hung SMC call. Do not claim the sanitizer tests prove blocked-kernel recovery.
- Sustained real-game calibration, subjective warm typing comfort/noise, human UI review and release notarization remain separate follow-ups. Exact CPU/GPU physical averages and Top semantics retain their existing disclosed limitations.

## Reproduction

```sh
Scripts/test.sh -j 1 --no-parallel
python3 -m unittest discover -s Tests/ToolTests -v
ASAN_OPTIONS=detect_leaks=0 Scripts/test.sh -j 1 --no-parallel --sanitize address
Scripts/test.sh -j 1 --no-parallel --sanitize thread --filter 'concurrentAdmission|pollingRestart|overlappingLifecycle|failedRelease|cancellingOneWaiter'
Scripts/build.sh -jobs 1
```

The genuinely signed executable supports fixed `--helper-security-check` and read-only `--performance-check`. Bounded `--profiles-recovery-heartbeat`, `--profiles-recovery-disconnect`, `--profiles-recovery-quit` and external-controller-SIGKILL `--profiles-recovery-hold` checks use a separate temporary profile store. Hold is limited to thirty seconds after rotating-fan readiness; it fails and releases if no external kill occurs. `--profiles-sleep-check` must only be armed with a coordinated wake. Never run fan diagnostics alongside an active controller. Always finish with verified System. Detailed artifacts live in ignored build/local folders.
