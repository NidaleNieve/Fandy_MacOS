# Safety

Fandy replaces macOS fan demand while a custom profile is active. Choose **System** to return control to macOS. Use one fan-control utility at a time.

## Cooling behavior

Each fan uses its own reported minimum and maximum RPM. A 0% custom setting means the supported minimum, not a stopped fan. Max requests the reported maximum immediately. Minimum airflow is a floor within Fandy's calculation; it does not preserve a higher fan demand that macOS would otherwise choose.

Under nominal or fair thermal pressure, demand comes from enabled curves, minimum airflow and an optional temperature target. There is no hidden temperature-triggered maximum-fan override. Serious, critical or unknown thermal pressure releases control directly to macOS. Fandy does not change clocks, power limits or thermal services.

Required chip readings remain mandatory even when a CPU/GPU curve selection is disabled. Missing or stale required readings, invalid metadata, conflicting ownership and failed transactions revoke control and attempt verified automatic restoration. CPU/GPU averages are estimates and Top proximity is a proxy; see [Compatibility](docs/COMPATIBILITY.md).

## Response and idle

Quiet averages demand over fifteen seconds and limits upward changes to two percentage points per second. Fast uses no averaging and permits ten points per second. A 20% response uses a twelve-second averaging window. Downward changes retain hysteresis and rate limits. Fresh actual speed seeds entry into custom control.

With Apple auto at idle enabled, fifteen seconds of zero demand releases the fans to macOS. Demand of at least 5% for three seconds permits reacquisition. A positive minimum airflow prevents that idle release. Fan inertia, firmware and macOS ownership can all produce speeds that differ temporarily from a requested target.

## Restoration and failures

The privileged helper authenticates the app and independently validates every admitted request. Connection-owned leases expire after ten seconds without an accepted target request. Active expiry decisions and failed-restoration retries use a 100 ms timer. Disconnect, System, normal quit and system sleep revoke pending work and request restoration.

Restoration attempts every known fan independently, releases a reviewed handover flag where applicable, and reads back final ownership. It does not depend on temperature readings or clear fan targets. Partial failures remain visible and are retried; RPM alone never proves that macOS owns a fan.

Startup restores automatic control before sensor initialization. After system sleep, fresh ownership and readings are required before any valid profile intent resumes. Display sleep does not suspend the controller. Installation and update preparation require verified handback before removing a helper registration.

A dead, suspended or kernel-blocked helper cannot run its watchdog. launchd restart can restore control only when the service and hardware I/O cooperate. The health channel can report stalled work, but cannot interrupt a blocked kernel call. These mechanisms reduce failure exposure without guaranteeing recovery in every hardware or operating-system failure.

## Tested hardware

The owner has physically tested the app on M2 Pro and M5 Pro MacBook Pros. Other M1–M5 notebook variants use reviewed reference recipes and runtime validation. Testing on those two machines does not establish every model's sensor accuracy, recovery timing, sleep/wake behavior or performance under sustained workloads.

AppleSMC fan control uses undocumented hardware interfaces. Tests with injected transports verify software decisions and command handling; they do not prove physical compatibility. New hardware transactions require the [hardware testing checks](docs/HARDWARE_GATES.md).
