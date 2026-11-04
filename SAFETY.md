# Safety

Fandy controls fan demand while a custom profile is active. Choose **System** to restore macOS control. Run one fan-control utility at a time.

## Cooling

During manual control, 0% means a fan's reported minimum RPM; Max uses its reported maximum. Each fan has its own bounds. Minimum airflow is a floor inside Fandy's calculation and may be lower than the speed macOS would choose.

Demand is the maximum of enabled curves, minimum airflow and an optional temperature target. There is no hidden temperature-triggered maximum-fan override. Serious, critical or unknown thermal pressure releases control directly to macOS. Fandy does not change clocks, power limits or thermal services.

Required chip readings remain mandatory when a chip curve is disabled. Missing or stale readings, invalid metadata, conflicting ownership and failed transactions trigger handback. CPU/GPU averages are estimates; Top proximity is a chassis proxy. See [Compatibility](docs/COMPATIBILITY.md).

## Response and idle

Quiet averages demand over fifteen seconds and limits rises to two percentage points per second. Fast has no averaging and permits ten points per second. At 20%, the averaging window is twelve seconds. Downward changes use hysteresis and rate limits. Entry into custom control starts from fresh actual fan speed.

Apple auto at idle releases control after fifteen seconds of zero demand. Demand of at least 5% for three seconds permits reacquisition. A positive airflow floor prevents idle release. macOS may stop or run the fans after handback; actual RPM can lag a target during transitions.

## Recovery

The helper authenticates requests and independently validates them. Leases expire after ten seconds without an accepted target request. A 100 ms timer handles active expiry and restoration retries. System, quit, disconnect and system sleep cancel pending work before handback.

Restoration attempts every known fan, releases the handover flag where applicable, and reads back final ownership. It works without temperature readings and leaves targets untouched. Partial failures are reported and retried. RPM alone cannot establish ownership.

Startup restores automatic mode before sensor initialization. Wake requires fresh readings and verified ownership before resuming a profile. Updates require handback before removing the old helper. Display sleep does not suspend control.

A dead, suspended or kernel-blocked helper cannot run its watchdog. launchd recovery depends on the service restarting and hardware I/O completing. The health channel reports stalled work but cannot interrupt it.

## Hardware coverage

Physically tested on M2 Pro and M5 Pro MacBook Pros. Other M1–M5 variants use reference adapters and runtime checks. AppleSMC fan control is undocumented; app testing does not certify sensor accuracy or every failure case. Software fixtures cover command handling, not physical compatibility. Changes to hardware transactions follow [Hardware testing](docs/HARDWARE_GATES.md).
