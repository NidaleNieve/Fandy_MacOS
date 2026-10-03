# Reliability and everyday-use improvements — 2026-10-02

## Implemented behavior

- Profile collection changes persist successfully before the editor publishes create, duplicate, delete, import or reorder results. Failed collection operations retain the previous collection and offer Retry. Live validated curve edits remain usable while their serialized background save is pending; the editor distinguishes unsaved changes from successful persistence. Older save revisions cannot overwrite newer requests. Quit releases fans before waiting for disk work.
- Profile reads are bounded to one MiB during acquisition, including when the file changes after the metadata check. Existing version-one archives, damaged-file preservation and protected built-ins are retained.
- Profile-level native Undo/Redo groups a complete drag or floor-slider gesture into one step. Interrupted gestures close their history group. Selection changes and collection changes clear obsolete history. Numerical submissions, reset and other valid edits participate in history; unpublished invalid drafts do not.
- Curve graphs support selected-point arrow keys (one degree or percent; Shift uses 0.1), and fresh qualified input markers. Invalid adjustments never leave the draft. A demand breakdown uses the engine's existing curve results and independent chip guard; fan percentage is explicitly normalized to hardware min/max rather than a promise of stopped fans.
- Settings provide explicit native launch-at-login registration, refreshed on return from System Settings. It is independent of helper registration and starts in System. This preference is not enabled by development tests.
- Native JSON import/export carries profile definitions only. Entire imports validate before committing, become custom profiles with fresh IDs and never activate themselves. Protected/reserved identities, authority fields, duplicate IDs, invalid curves, excessive nesting/count/bytes and unsupported versions are rejected. Duplicate names are allowed. Exporting a built-in produces a custom definition.
- Diagnostic export uses an allowlist of version/model/state/health/stage/ownership and fixed failure categories. Arbitrary error messages, custom profile names, paths, signing identity, sensor recordings and previous selections are excluded. Export is local through a native file panel.
- Rotating diagnostic writes run on a utility queue with at most one outstanding record. Backpressure drops diagnostic records instead of delaying control. Mutable admission and file operations have separate locks. Required sensor reads are unchanged; immutable key membership is computed once instead of sorted on every acquisition.
- Software-only CI runs Swift/tool tests and a separate sanitizer job. It never registers a helper, launches fan diagnostics or contains signing credentials. Hosted CI execution is not yet verified by a remote run.

## Interfaces and reproducibility

`ProfilePersistence` serializes revisioned saves. `ProfileInterchange` defines the version-one profile-only file format. Existing persisted `ProfileArchive` and the five-method privileged protocol are unchanged. `ProfileStore.readBounded` limits native-panel imports and archive reads. No new root authority or filesystem operation is exposed.

```sh
Scripts/verify.sh
Scripts/verify.sh --sanitizers
Scripts/verify.sh --native-build
```

The first two commands execute software-only tests. The native option compiles an unsigned app; signed local delivery uses the existing single-job build and private signing configuration. CI uses the selected macOS runner's toolchain and will report incompatible SDK/compiler APIs as failures; local compilation alone is not evidence of a hosted CI pass.

Fixed signed `--performance-monitoring-long` and `--performance-comfort-long` actions each run thirty minutes with no caller-selected duration, target, sensor authority or workload stimulus. Comfort uses the existing production Cool Chassis policy. They abort on failed freshness/eligibility or elevated thermal pressure and request System on exit. The read-only `Scripts/performance_processes.py` samples supplied local process IDs for thirty minutes. Raw output belongs in ignored build/local directories and is not included in sanitized export.

## Verification and remaining measurements

Software tests: **235 Swift** (28 hardware, 157 core, 50 app), including bounded reads, revision ordering, atomic failed-operation retry, authority rejection, fresh import identities, grouped Undo/Redo, interrupted gestures and export privacy. **33 Python tool tests** include process-time parsing. Full Address Sanitizer and six selected Thread Sanitizer cases pass. Leak detection is disabled in ASan; no general leak-free claim follows.

The signed native build and strict/deep signatures pass. System-first functional launch passed five real ticks with both fans in automatic mode. The refreshed genuine signed negative-input check passed eleven checks. The sequential temperature-profile regression passed System+, Gaming, Cool Chassis, School, custom editing, backend round trip, rapid switching and both-fan System restoration.

An initial profile/performance overlap invalidated both runs: an independently started System diagnostic released control while the profile check was active. Both stopped and automatic control was verified before the profile check was repeated alone. The successful sequential result supersedes that interrupted run; it is not counted as a pass. All physical checks must remain exclusive and sequential. A later read-only long-session setup was intentionally stopped before the active phase to add native power observation without a second polling loop; its partial samples are not a completed benchmark. Long sessions now invalidate on any native power transition.

Final latency, heartbeat and long-session results are appended after completion. Physical active sleep/wake still requires a coordinated human wake. No sleep test is armed without that coordination. Editor-open measurements and native visual/accessibility review require human interaction; no screenshots or automated GUI navigation are used. Subjective typing comfort, acoustic calibration and sustained actual-game calibration remain human-dependent follow-ups. No default curve has been retuned from cold idle observations.

## Completed long-session results — 2026-10-03

Both exclusive thirty-minute native controller sessions completed with fresh required readings, maintained selected policy and independently verified automatic restoration. These diagnostic GUI sessions measure the controller path with the editor closed; they do not measure editor rendering or establish battery-life improvement. A later ordinary workload changed during the active session, so the two sessions are not a controlled thermal/energy comparison.

| Session | Diagnostic GUI CPU | Helper CPU | GUI median resident memory | Helper median resident memory | Full tick p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| System, 1,658 ticks | 0.12% | 1.10% | 86.89 MiB | 11.69 MiB | 51.14 ms |
| Cool Chassis, 1,504 ticks | 0.15% | 6.23% | 86.86 MiB | 10.91 MiB | 358.29 ms |

CPU percentages are accumulated process CPU time divided by elapsed time, expressed relative to one core. Resident memory is sampled RSS, which excludes compressed memory and is not a complete allocation/leak measurement. Active GUI RSS ranged 23.39–89.56 MiB; helper RSS ranged 9.44–12.33 MiB. Initial process startup and subsequent OS reclamation affect the range; no leak-free or energy-impact guarantee follows.

The System tick maximum was 86.05 ms; active tick maximum was 782.82 ms. The active full tick includes status, evaluation and target transaction work; it is not interchangeable with the separate helper-status latency budget. LongPerformancePassed checks session continuity/freshness/policy and handback, not a new active latency-budget certification. Polling sleeps one second after work, so the effective cadence includes tick duration. Active overhead and transaction latency remain measured optimization opportunities; safety sampling, required-key membership and physical write behavior were not weakened to claim an improvement.

The final paced short check separately passed acquisition p95 **30.82 ms**, helper status p95 **37.66 ms** and engine evaluation p95 **0.083 ms** against their existing 100/250/10 ms budgets. Bounded heartbeat recovery independently observed both fans automatic after approximately **10.19 seconds** from rotating manual control. Existing restart/disconnect/SIGKILL evidence remains documented in the previous review; those unchanged paths were not all repeated in this cycle.

Most active-session samples held approximately 3,420 RPM. Late in the session the real chip envelope rose to approximately 86.9°C while thermal pressure remained nominal; the independent chip guard demanded maximum cooling and actual RPM rose toward the reported maximum. The diagnostic created no CPU/GPU stimulus. This demonstrates real escalation during ordinary external activity, not a sustained gaming calibration or proof of individual CPU/GPU sensor identity. Final independent mode readback was **0/0**, with Apple still requesting cooling; automatic ownership does not imply stopped fans. The normal signed GUI was then launched in System.

The actual coordinated sleep/wake test, editor-open/human UI review, subjective typing acoustics and real-game calibration remain pending. The hosted workflow is configured but its remote execution must be verified after publication.
