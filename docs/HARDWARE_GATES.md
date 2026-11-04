# Hardware testing

Test changes with injected transports before physical writes. Keep raw measurements, signing settings and operator notes in ignored local storage.

## Prepare

- Stop other fan controllers, including their helpers.
- Use the signed app and helper in `/Applications/Fandy.app`. Preserve signing identity and user configuration.
- Check the actual model, fan topology, modes, targets and individual RPM bounds. Failed required reads or unknown ownership block the test.
- Independently verify automatic ownership. Start with a bounded, modest upward request within the observed limits, without a heat workload.

The helper owns admission and deadlines. Do not try alternate keys or write sequences after a failed transaction.

## Verify

Record each fan's initial mode, requested target, acknowledgement, actual rotation and final ownership. Check independently of the controller's success message; RPM alone does not prove handback.

A new recipe needs System handback, partial-failure cleanup, quit, disconnect, heartbeat expiry and controller-termination tests. Check helper restart and actual system sleep/wake separately. Record blocked I/O or helper death as limitations: the watchdog cannot run while execution is stopped.

Sensor changes need model-specific source information, types, acquisition timing and an account of missing members or competing identities. Temperature similarity alone cannot establish a mapping. Exercise the production adapter as well as the encoder.

## Finish

End every live session in independently verified System mode. If restoration fails, stop testing and resolve ownership before replacing or unregistering the helper. Keep the registered bundle until handback and removal are confirmed.

Public builds need software verification, matching app/helper signatures, notarization, stapling, Gatekeeper assessment and mounted-payload checks. Record the tested model and scope in [Compatibility](COMPATIBILITY.md). [Safety](../SAFETY.md) describes operating limits.
