# Hardware testing

Hardware changes need tests with injected transports before any physical write. A passing fixture demonstrates software behavior; it cannot qualify a Mac's physical fan interface.

## Before a live test

- Stop other active fan controllers and confirm that their helpers are not still controlling the fans.
- Use the correctly signed app and helper installed under `/Applications/Fandy.app`. Preserve the existing signing identity and user configuration.
- Read the actual model, fan topology, modes, target metadata and individual RPM bounds. Unknown ownership or failed required readings block the trial.
- Begin with independently verified automatic ownership. Use a bounded, modest upward request within the observed limits; avoid a heat workload or a downward cooling experiment as an initial test.

The helper owns admission, cancellation and deadlines. A caller cannot grant sensor evidence, extend a fixed qualification deadline or select arbitrary SMC keys. Do not try alternate write sequences after a failed transaction.

## What to verify

Record the initial state, requested target, mode acknowledgement, actual rotation and final ownership independently of the controller's success message. Check each fan separately. A selected profile, accepted command, positive RPM or still-running process does not prove the full transaction succeeded.

Before accepting a new control recipe, verify System handback, partial-failure cleanup, normal quit, disconnect, heartbeat expiry and controller termination. Evaluate helper restart and actual system sleep/wake separately where those are in scope. A timer cannot run during helper death or blocked kernel I/O; record that limitation rather than treating a timeout as successful recovery.

Sensor changes need model-specific provenance, data types, fresh acquisition and an explanation of missing members or competing identities. Similar temperatures or correlation alone do not prove a physical mapping. Test the actual production adapter, not only an isolated encoder.

## Finish and release

End every live session in independently verified System mode. If restoration fails, stop further experiments and resolve ownership before replacing or unregistering the helper. Preserve the registered bundle until release and removal are confirmed.

Keep raw measurements, operator notes and signing configuration in ignored local storage. Public compatibility documentation should state the tested model and scope without publishing recordings. A public build must pass software verification, matching app/helper signatures, notarization, stapling, Gatekeeper assessment and final mounted-payload checks.

The owner has tested M2 Pro and M5 Pro hardware. Further testing should address a specific new model, changed transaction or unresolved behavior; those results do not need another accumulated delivery diary. See [Compatibility](COMPATIBILITY.md) for current support and [Safety](../SAFETY.md) for operating limits.
