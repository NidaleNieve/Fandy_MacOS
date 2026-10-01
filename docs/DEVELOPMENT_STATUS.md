# Development checkpoint — 2026-10-01

## Current stage

Fandy has its native menu-bar/editor UI, profile CRUD, graphical curves, persistence, real monitoring and shadow calculations. The signed root helper is enabled through SMAppService with model-specific automatic restoration and a new, separate bounded mechanical qualification endpoint. App identity remains `is.dsr.fandy`; local signing is preserved. Ordinary real profiles remain disabled: all twelve sensor roles/coverage and live recovery proof are pending.

Earlier both-fan manual-to-automatic handback, three idempotent releases and60 seconds without mode reversion passed. Current attempts have not spun fans: automatic-mode target preload read back zero; mode-first fan0 activation briefly read1 with target0, so Fandy aborted and restored both to0. Filling the type field did not fix the target. These are failed trials, not qualified manual control.

The installed correction queries and verifies metadata on the writing connection immediately before each write, following reviewed reference writers. It has passed injected tests and a signed build. **Physical retry is pending exclusive ownership:** TG Pro's privileged helper survived GUI exit. Automatic approval review rejected the next trial until that competing service is stopped; stopping it requires local administrator authentication. Both fans remain verified automatic.

## Implemented recovery path

`RecoveryTrialCoordinator` owns fresh readings, fixed targets, connection/session identity, absolute deadlines, heartbeat and per-fan release. Callers supply no RPM, keys, fan IDs, duration or qualification authority. Initial trial5 seconds; recovery trials15 seconds; heartbeat10 seconds; helper timer100ms. First and later restoration evidence are separate.

An explicitly approved stopped baseline requires both speeds/targets0 and a raw diagnostic peak below60°C. Targets are each reported spinning minimum+200, not an invented200 RPM command. Spinning admission keeps target-first verification and never falls back after failed preloading. All command construction is injected-transport tested. Generic physical setManual/setTarget still reject and profile leases cannot be admitted.

The wider Tp/Tm/Tg diagnostic domain and required candidate readings are checked for availability/freshness/finite values during finite trials. They do not prove sensor identity or chip coverage and cannot unlock ordinary control. A dead, suspended or blocked helper cannot execute its watchdog.

## Validation

Latest retained source verification: **144 passing Swift tests** (15 hardware,110 core,19 app), **27 passing Python tool tests**, successful single-job signed native compilation and strict deep signature verification. Final client stale-reply/protocol-stage and runtime conflict guard changes are included in this checkpoint. No screenshots, GUI automation, Max experiment, target clearing, power changes or thermal-service manipulation.

Existing authentication, bounded ingress, restoration coalescing, interpolation, aggregation, persistence and failure tests remain. New tests cover mechanical authority separation, strict fixed messages, stopped baseline, command order/metadata, partial activation, deadlines, heartbeat ownership/expiry, sensor/thermal faults and first-handback retention.

## Next work in order

1. Stop the competing TG Pro helper while both fans are automatic; verify absence and fresh mode0 on both. Keep its GUI closed during Fandy trials.
2. Run one fixed five-second initial request using the same-connection correction. If target readback still fails, preserve exact evidence and diagnose without bypassing it. Restore both fans after any failure.
3. After actual modest target/spin-up works, prove hard deadline, heartbeat expiry, disconnect and signed GUI-process SIGKILL using independent fan readings and restoration timings.
4. Finish live helper restart, malformed owned request, invalid/stale sensor, normal quit, rapid switching and practical sleep/wake tests. Document what was measured versus model-tested; helper death/blocking has a residual recovery window.
5. Qualify every sensor role with reviewed exact-model provenance/coverage and discriminating readings. Resolve CPU Tp/Tm cluster and GPU-region coverage, Trackpad/Actuator, three Airflow and three proximity roles. Existing reference correlation alone is insufficient; normal Fandy must read independently.
6. Enable ordinary physical writer/profiles only after complete recovery and sensor evidence. Then compare System/System+/Cool Chassis with human comfort feedback, using27°C Trackpad /25°C Actuator /33°C Airflow as calibration, not forced targets. Gaming tuning follows separately.
7. Complete native human UI review and release/distribution acceptance. No telemetry, network runtime, broad root APIs, updater or power manipulation is planned.

## Resume

Read this file, [hardware gates](HARDWARE_GATES.md), [qualification protocol](MANUAL_QUALIFICATION.md), [sensor evidence](SENSOR_EVIDENCE.md) and [security review](SECURITY_REVIEW.md). Ignored `docs/local/DEVELOPMENT_HANDOFF.md` contains private artifact paths/runtime detail; never publish it or raw CSV/logs/signing files.

```sh
Scripts/test.sh -j 1 --no-parallel
python3 -m unittest discover -s Tests/ToolTests -v
Scripts/build.sh -jobs 1
```

Regenerate the native project after new app/helper files with `Scripts/generate-project.py`. Do not overwrite `build/MonitoringDSR/Fandy.app` while registered: authenticated restore/unregister, confirm helper absent, replace the signed bundle, then register normally. CLI `--helper-restoration-status` / `--helper-restore` are safe read/release diagnostics. Fixed `--helper-recovery-initial`, `--helper-recovery-deadline`, `--helper-recovery-heartbeat`, `--helper-recovery-disconnect` and `--helper-recovery-hold` perform physical bounded trials only after exclusive ownership is established. Ordinary menu profiles still cannot activate.

The helper now independently checks for the known TG Pro privileged-controller executable through bounded kernel process metadata enumeration before admission and during a trial. Only a fixed blocker string is exposed over status; no PID/path or arbitrary process operation is accepted. This detects the present conflict, not every possible controller. Continuous fan mode/target checks remain required. Enumeration failure blocks trials; restoration is independent of this guard.

The installed root guard reported the TG Pro conflict correctly. The updated fixed non-activating protocol diagnostic passed all nine checks, with both fans automatic. Production monitoring launch/quit and three independent reads are recorded locally; no further physical trial was attempted while ownership remained blocked.
