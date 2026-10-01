# Hardware qualification gates

Current implementation supports reviewed Mac17,9 Apple Silicon hardware for read-only monitoring and automatic restoration. Physical manual-mode and target-RPM implementations reject all requests. Qualification is compiled into signed code, model-specific, and never granted by preferences or XPC payloads.

| Gate | State |
| --- | --- |
| Research and licensing | Sources inspected; provenance and license notices retained. Source behavior is distinct from firmware proof. |
| Pure models and native UI | Curve, aggregation, persistence, authentication, lifecycle, mock and qualification tests implemented. Real monitoring is the default. |
| All requested sensor identities and chip coverage | Pending. Every requested role is mandatory before manual testing. See [sensor requirements](SENSOR_EVIDENCE.md). |
| Automatic restoration | A local manual-to-automatic transition was verified on both fans, followed by three idempotent requests and sixty seconds of independent mode observation. Raw evidence stays private. Already-automatic observations prove idempotence only. |
| Modest manual request | Not attempted. Requires sensor/restoration gates and reviewed transaction order, then fixed +200 RPM for five seconds and verified release. |
| Live watchdog recovery | Pending. Actual GUI SIGKILL, disconnect and heartbeat expiry while owning manual fans are mandatory. Model tests do not prove physical recovery. |
| Failure matrix | Pending. Helper restart, malformed inputs, sensor faults, quit, rapid switching and sleep/wake require independent observations. |
| Profiles and calibration | Disabled until all manual/recovery gates pass. Comfort and gaming tuning follow separately. |

## Restoration requirements

Release authority is temperature-independent, restricted to reviewed model/topology and canonical per-fan metadata. Record pre-write mode, command outcome, immediate/final readback. Attempt the other fan after partial failure; overall success requires every fan's confirmed automatic mode. Never clear targets, guess alternate keys, accept unknown modes, or infer ownership from RPM alone.

Competing controllers must not reassert manual ownership. Idle external manual mode reports a conflict rather than starting an automatic-write fight. Failed Fandy releases still retry. Preserve the registered service bundle separately from build output.

## Manual qualification requirements

The [bounded qualification model](MANUAL_QUALIFICATION.md) has no physical writer or XPC endpoint. Admission requires every qualified sensor role, fresh automatic ownership, valid fan limits and conservative thermal pressure. The helper calculates exactly 200 RPM above each fresh actual speed; skip the whole trial if either fan is stopped or lacks the margin. No Max-first or downward-speed experiment.

The first trial expires after five seconds. Recovery trials expire after fifteen seconds regardless of heartbeat, or earlier after ten seconds without heartbeat. Restore and independently verify both fans after every trial. Never mark production control qualified to unlock test authority.

A dead, suspended or blocked helper cannot execute its watchdog. Launchd restart recovery requires live testing and honest documentation. Unreliable restoration blocks custom control. Startup/wake remain System-first; no manual state is restored from disk.

Use logs, programmatic readings, compilation and model tests. No screenshots, Computer Use, GUI automation, thermal-service manipulation or claimed Apple fan-floor behavior. Raw recordings, diagnostics, signing identities and detailed local verification reports stay outside the public Git tree.
