# Compatibility

Fandy targets M1–M5 MacBook Pros on macOS 15 or later. Intel Macs and fanless MacBook Airs are unsupported.

Physically tested on M2 Pro and M5 Pro MacBook Pros. Other variants use reference adapters checked at runtime.

| Family | Compiled model identifiers | Physical testing |
| --- | --- | --- |
| M1 | MacBookPro17,1; MacBookPro18,1–4 | Reference-supported |
| M2 | Mac14,5; Mac14,6; Mac14,7; Mac14,9; Mac14,10 | M2 Pro tested |
| M3 | Mac15,3; Mac15,6–11 | Reference-supported |
| M4 | Mac16,1; Mac16,5–8 | Reference-supported |
| M5 | Mac17,2; Mac17,6–9 | M5 Pro tested |

Testing a chip variant does not cover every configuration, firmware version or recovery case.

## Runtime checks

Model ID, Apple Silicon capability and chip generation must agree. The helper checks one or two fans, their mode/target metadata and separate RPM bounds. Unsupported metadata blocks custom control; temperature monitoring may still work.

Max needs valid fan metadata. Temperature profiles also need complete, fresh sensor groups. Membership is fixed at startup; a missing selected member invalidates the group. System restoration works independently of temperature reads.

Mac17,9 uses a fixed 105-key chip envelope. Other notebooks use generation-specific CPU/GPU groups from [Stats](https://github.com/exelban/stats/blob/9ceb6e3b20001c4102f473c5dc3e96b388a77da9/Modules/Sensors/values.swift). Disabling a chip curve does not remove required chip checks.

CPU/GPU averages describe sensor groups rather than certified core membership. Trackpad and actuator have separate temperature scales. Airflow combines Left, Right and **Top proximity**, an ambient proxy. Charger and power-supply candidates are informational.

Some adapters use `Ftst` for protected firmware handover. Recovery must be checked on that interface; a dead or blocked helper cannot execute it. See [Safety](../SAFETY.md) and [Hardware testing](HARDWARE_GATES.md). CI checks compilation on supported macOS runners; live OS and hardware coverage require separate tests.

Reference licenses are in [Third-party notices](../THIRD_PARTY_NOTICES.md).
