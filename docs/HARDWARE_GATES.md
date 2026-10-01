# Hardware qualification gates

Current signed authority is model-specific `recoveryQualification`: real monitoring, independently qualified automatic restoration and a separate bounded mechanical trial. Ordinary profile leases, arbitrary RPM/manual operations, automatic target clearing and unknown modes remain unavailable. Preferences and XPC payloads cannot grant authority.

| Gate | Actual state |
| --- | --- |
| Research / licensing / pure models / UI | Implemented; real monitoring is default and simulation is explicit. |
| All requested sensor roles and coverage | Identity/coverage evidence remains pending. The revised roadmap qualifies sensors by policy requirements; production gating changes are still to be implemented. Mechanical tests qualify no mappings. |
| Automatic restoration | Both mode1→0 transitions, three idempotent requests and 60 seconds of independent mode observations previously passed. |
| First modest manual trial | Passed: a single 2517 RPM request per fan, observed spin-up, five-second expiry and both mode1→0 handbacks. Bounded acknowledgement fixed premature readback. |
| Exact write sequence | Same-connection metadata/write and bounded readback passed injected tests and physical modest trials. |
| Live watchdog / disconnect / SIGKILL | Passed live heartbeat expiry, disconnect, fixed deadline and signed controller SIGKILL with independent mode reads. |
| Helper restart / malformed inputs / sensor faults / quit / switching / sleep | Helper death/restart and physical sleep/wake remain pending. Dead/blocked-helper limitation remains explicit. |
| Real profiles / calibration | Ordinary control remains disabled; next is fixed System/Max after minimum recovery, then chip/comfort features by their actual sensor requirements. |

## Release requirements

Restoration is temperature-independent and restricted to reviewed model IDs0/1 and canonical lowercase mode metadata. It records initial mode, command result, immediate and later readbacks, attempts the other fan on partial failure, and fails overall if either is unverified. Never infer ownership from RPM or clear targets as an undocumented side effect. Mode3 or changed metadata is rejected.

Competing controllers must be stopped before qualification; no automatic-write fight is allowed. TG Pro's closed GUI previously left its root helper running and a trial was blocked. The user then stopped that service; absence was verified before the successful tests above. No running Macs Fan Control or ThermalForge controller/helper was identified. Installed applications alone do not establish active ownership.

## Bounded trial requirements

See [the exact qualification protocol](MANUAL_QUALIFICATION.md). Helper-derived targets stay upward and within separately read fan bounds. Stopped/zero-target/cool admission permits a distinct minimum+200 mode-first sequence; spinning admission requires successful automatic preloading. No sequence fallback, Max-first, downward cooling test, Ftst, thermal-daemon manipulation or caller-selected target is permitted.

Initial expiry is five seconds; recovery expiry is fifteen seconds regardless of heartbeat, or ten seconds without heartbeat. Restore and independently verify both fans after every attempt. Status retains the first handback evidence separately from later releases. A timer cannot run while the helper is dead or blocked; actual restart behavior must be measured honestly.

After first activation works, prove each recovery case with independent mode/RPM logs. Any unreliable release blocks general control. Startup/wake remain System-first. Sensor qualification must record provenance, type, timing, alternatives and uncertainty; temperature resemblance alone cannot pass a role.

No screenshots, Computer Use or GUI automation. Raw reference CSV, recordings, operator details and signing configuration stay outside public Git. Preserve the registered bundle and unregister through verified release before replacement.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.
