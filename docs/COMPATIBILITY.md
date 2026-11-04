# Compatibility

Fandy targets M1–M5 MacBook Pros running macOS 15 or later. Intel Macs and fanless MacBook Airs are unsupported for fan control.

## Tested hardware

The owner has physically tested the app on M2 Pro and M5 Pro MacBook Pros. The remaining variants use reviewed reference implementations and runtime checks.

| Family | Compiled notebook identifiers | Physical testing |
| --- | --- | --- |
| M1 | MacBookPro17,1; MacBookPro18,1–4 | Other hardware testing is still needed. |
| M2 | Mac14,5; Mac14,6; Mac14,7; Mac14,9; Mac14,10 | M2 Pro tested by the owner; other variants remain reference-supported. |
| M3 | Mac15,3; Mac15,6–11 | Other hardware testing is still needed. |
| M4 | Mac16,1; Mac16,5–8 | Other hardware testing is still needed. |
| M5 | Mac17,2; Mac17,6–9 | M5 Pro tested by the owner; other variants remain reference-supported. |

Owner testing is real-machine evidence. It does not establish a complete recovery, installation, sleep/wake or thermal-calibration matrix on either family. The compiled registry's evidence flags and adapter choices remain unchanged; documenting the M2 Pro result does not bypass runtime checks or enable the M5-specific optimizations on another model.

## Runtime requirements

The notebook identifier, Apple Silicon capability and chip generation must agree. The helper discovers one or two fans, validates mode/target metadata and reads each fan's own RPM limits. Unknown or contradictory metadata prevents custom control. Monitoring can remain available when control is unavailable.

System restoration is independent of temperature acquisition. Max requires valid fan metadata. Temperature profiles additionally require complete, fresh readings for their selected policy. Startup resolves explicit sensor groups and then freezes their membership; a later missing member cannot silently disappear from a maximum or average.

On Mac17,9, chip control uses a fixed 105-key envelope. Other supported notebooks use model-family CPU/GPU groups adapted from [Stats at the pinned revision](https://github.com/exelban/stats/blob/9ceb6e3b20001c4102f473c5dc3e96b388a77da9/Modules/Sensors/values.swift). The full required chip inputs remain checked even if a profile disables a chip curve. Chassis curves and targets also require their own inputs.

CPU/GPU averages describe the selected sensor groups, not certified physical core membership. Trackpad and actuator readings have separate scales. Airflow uses Left, Right and **Top proximity**; the latter is a proxy rather than a certified surface or exact Airflow Top sensor. Charger and power-supply candidates are informational.

## Hardware interfaces and limits

Reviewed adapters support lowercase/uppercase mode keys and supported float/fixed-point RPM formats. Some reference paths require a bounded `Ftst` handover. That flag changes firmware ownership; successful operation or recovery on one interface does not establish it on every model.

Transactions validate ownership, bounds, required readings and cancellation before and after hardware calls. System handback attempts every fan and independently verifies the final modes and handover flag. A dead or blocked helper cannot execute recovery code. See [Safety](../SAFETY.md) and the [hardware testing requirements](HARDWARE_GATES.md).

The macOS deployment target and CI builds establish compilation coverage. They do not establish live behavior on every macOS release. Reference provenance and licenses are retained in [Third-party notices](../THIRD_PARTY_NOTICES.md).
