> Temperature integration update: [current results and blockers](TEMPERATURE_PROFILE_STATUS.md). Four comfort roles are reviewed. The curve-qualification stage and helper-owned 15-second deadline are implemented/tested but inactive in the delivered maximum-only build.

# Hardware qualification gates

Current signed authority is model-specific `maximumControl`: real monitoring, verified automatic restoration and production fixed Max leases. Temperature profiles require their own evidence. Arbitrary sensor-free RPM, independent manual-mode primitives, automatic target clearing and unknown modes remain unavailable. Preferences and XPC payloads cannot grant authority.

| Gate | Actual state |
| --- | --- |
| Research / licensing / pure models / UI | Implemented; real monitoring is default and simulation is explicit. |
| All requested sensor roles and coverage | Identity/coverage evidence remains pending. The revised roadmap qualifies sensors by policy requirements; production gating is now policy-specific. Mechanical tests qualify no mappings. |
| Automatic restoration | Both mode1→0 transitions, three idempotent requests and 60 seconds of independent mode observations previously passed. |
| First modest manual trial | Passed: a single 2517 RPM request per fan, observed spin-up, five-second expiry and both mode1→0 handbacks. Bounded acknowledgement fixed premature readback. |
| Exact write sequence | Same-connection metadata/write and bounded readback passed injected tests and physical modest trials. |
| Live watchdog / disconnect / SIGKILL | Passed live heartbeat expiry, disconnect, fixed deadline and signed controller SIGKILL with independent mode reads. |
| Helper restart / malformed inputs / sensor faults / quit / switching / sleep | Live helper SIGKILL/restart handback passed. Physical sleep/wake remains pending. Dead/blocked-helper limitation remains explicit. |
| Real profiles / calibration | System/Max are physically operational. Chip/comfort profiles await only their required sensor evidence, then bounded activation/calibration. |

## Release requirements

Restoration is temperature-independent and restricted to reviewed model IDs0/1 and canonical lowercase mode metadata. It records initial mode, command result, immediate and later readbacks, attempts the other fan on partial failure, and fails overall if either is unverified. Never infer ownership from RPM or clear targets as an undocumented side effect. Mode3 or changed metadata is rejected.

Competing controllers must be stopped before qualification; no automatic-write fight is allowed. TG Pro's closed GUI previously left its root helper running and a trial was blocked. The user then stopped that service; absence was verified before the successful tests above. No running Macs Fan Control or ThermalForge controller/helper was identified. Installed applications alone do not establish active ownership.

## Bounded trial requirements

See [the exact qualification protocol](MANUAL_QUALIFICATION.md). Helper-derived targets stay upward and within separately read fan bounds. Stopped/zero-target/cool admission permits a distinct minimum+200 mode-first sequence; spinning admission requires successful automatic preloading. No sequence fallback, Max-first, downward cooling test, Ftst, thermal-daemon manipulation or caller-selected target is permitted.

Initial expiry is five seconds; recovery expiry is fifteen seconds regardless of heartbeat, or ten seconds without heartbeat. Restore and independently verify both fans after every attempt. Status retains the first handback evidence separately from later releases. A timer cannot run while the helper is dead or blocked; actual restart behavior must be measured honestly.

After first activation works, prove each recovery case with independent mode/RPM logs. Any unreliable release blocks general control. Startup/wake remain System-first. Sensor qualification must record provenance, type, timing, alternatives and uncertainty; temperature resemblance alone cannot pass a role.

No screenshots, Computer Use or GUI automation. Raw reference CSV, recordings, operator details and signing configuration stay outside public Git. Preserve the registered bundle and unregister through verified release before replacement.

The current mechanical path enforces a helper-side check for TG Pro's known privileged executable before admission and during ownership. Status exposes only a fixed blocker message, never process identifiers or paths. Bounded kernel process metadata enumeration provides no generic process/filesystem API to a caller. This detects a known conflict, not universal exclusive-ownership proof; modes/targets still require continuous checking. Safe restoration remains available despite that blocker.

## Production acceptance

The app-model Max diagnostic observed actual RPM near each reported maximum, then verified both modes 0 after System. Production Max lease SIGKILL and heartbeat expiry passed with independent mode observations and both initial-mode-1 restoration reports. Normal termination is exercised directly from active Max by a fixed native diagnostic. 157 Swift tests and signed native build pass. The helper self-kill diagnostic was temporary and removed; the dead/blocked-helper limitation remains documented.
