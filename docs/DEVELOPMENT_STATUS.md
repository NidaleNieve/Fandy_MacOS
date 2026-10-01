# Development checkpoint — 2026-10-01

## Actual working state

Fandy has a native menu-bar UI, profile CRUD, editable graphical curves, versioned persistence, deterministic simulation, real read-only monitoring, and shadow demand calculations. The signed restoration-only helper is installed and enabled on the qualified Mac17,9 topology. System can request automatic mode independently of temperature qualification. Custom profiles remain previews: physical manual-mode and target methods still reject requests.

Automatic handback has been physically demonstrated on both fans: an observed mode 1 → mode 0 transition, three successful idempotent requests and 60 seconds of independent automatic-mode observations. This is not proof of recovery from a future Fandy manual transaction. Final checkpoint observations show both fans in mode 0; the registered app/helper binaries match the final build.

**Verification:** 111 passing Swift tests (8 hardware, 85 core, 18 app), 27 passing Python tool tests, successful single-job signed native build and strict deep signature verification. No screenshots, GUI automation, manual RPM writes, target clearing or Max experiments were used.

## Security work completed at this checkpoint

- Authentication requires the expected signed app identity and signing team; wrong-identity and ad-hoc callers were rejected in live tests.
- Helper admission is bounded before serial dispatch: eight connections, four ordinary requests globally/two per peer, size and rate checks, separately reserved restoration capacity, and coalesced rejection handling. Closing connections cannot revive queued commands.
- Overlapping GUI restoration calls share one flight; cancellation does not cancel the shared release and later requests retry freshly. Generation checks prevent stale replies from changing current state.
- Fixed signed protocol diagnostics passed malformed, oversized, unknown-role, overflow, unqualified-lease and forged-target rejection, reconnection and wrong-helper-identity checks. They do not issue fan commands.
- The inert manual qualification model rejects stopped fans, including hardware reporting a zero minimum.

This is a reviewed restoration-only surface, not final security acceptance of a manual writer that does not yet exist. A dead, suspended or blocked helper cannot execute its watchdog; bounded admission does not solve blocked hardware I/O.

## Remaining work, in order

1. **Qualify all twelve sensor roles.** CPU/GPU average and peak coverage plus Trackpad, Actuator, three Airflow and three proximity roles remain pending. Published keys are candidates; rounded reference agreement and historical names are insufficient. Resolve CPU cluster/coverage and GPU-region ambiguity, and the Airflow Top/Power Supply provenance conflicts. Obtain supported identifier diagnostics or a targeted discriminating read-only measurement. Do not repeat idle recordings without a new hypothesis. Production readings must remain independent of the reference application.
2. **Review and implement a narrowly bounded manual qualification operation.** Only after every sensor role passes, review exact hardware target metadata, encoding, stale-target behavior and transaction order. Test construction through injected transport first. The helper must calculate fresh per-fan actual RPM + 200, skip the whole trial if either fan is stopped or lacks margin, enforce five seconds initially and at most fifteen seconds for recovery trials, and restore both fans. Callers must not supply arbitrary keys, RPM, durations or qualification authority. The existing pure model grants no physical authority.
3. **Prove real recovery while owning manual control.** Establish exclusive ownership first. Verify GUI SIGKILL, disconnect, heartbeat expiry, helper restart, invalid/stale sensors, malformed requests, quit, rapid switching and sleep/wake through independent mode/RPM observations and timings. Model tests and automatic-only diagnostics do not replace these physical tests. Any unreliable handback blocks general control. Document blocked/dead-helper limitations honestly.
4. **Enable production profiles only after the full recovery matrix passes.** Keep startup/wake System-first, acknowledge activation before checkmarks, validate actual per-fan bounds, and re-review the new helper surface. Do not claim an Apple-preserving fan floor; manual mode is assumed to replace normal demand until independently proved otherwise.
5. **Calibrate comfort, then gaming.** Compare System/System+/Cool Chassis under similar light workloads and human comfort/noise feedback. Comfortable references are Trackpad about 27°C, Actuator 25°C, Airflow 33°C; warmer references are about 31°C/29°C/43–44°C. Separate sensor scales and use maximum demand; do not force exact temperatures. The initial 20% floor is normalized between spinning min/max and is not an acoustic result. Gaming calibration follows separately.
6. **Finish acceptance and distribution.** Human native-UI review, real lifecycle acceptance, install/uninstall verification, final permissions/signing/security review, accurate documentation and any requested release packaging remain. Additional models require their own evidence. No telemetry, updater, power-setting changes or broad helper APIs are planned.

## Resume and verify

Read this checkpoint, `docs/HARDWARE_GATES.md`, `docs/SENSOR_EVIDENCE.md`, `docs/MANUAL_QUALIFICATION.md` and `docs/SECURITY_REVIEW.md` first. The development machine also has an ignored, more detailed `docs/local/DEVELOPMENT_HANDOFF.md` with private artifact locations and exact runtime state. Never publish that private handoff, reference CSV, raw logs or local signing configuration.

```sh
Scripts/test.sh -j 1 --no-parallel
python3 -m unittest discover -s Tests/ToolTests -v
Scripts/build.sh -jobs 1
```

Regenerate the native project after adding app/helper source files using `Scripts/generate-project.py`; it preserves local signing choices in ignored configuration files. Do not overwrite or delete the registered `build/MonitoringDSR/Fandy.app` while the service is registered. Use the authenticated restoration/unregister path before replacement.

Start the next session with fresh read-only helper status and fan modes, then sensor-evidence work. Do not restart broad testing or attempt manual activation merely because the UI is complete.
