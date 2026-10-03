# Temperature goals and discoverable rename — 2026-10-03

## Temperature goal

Editable profiles have an optional Target temperature control at the top of Fan Curves. Choose Chip (hottest qualified control input), Trackpad, Actuator or hottest Airflow and enter Celsius. Existing profiles default to no target. System and Max remain immutable.

The target is an additional proportional cooling request, not a precision thermostat or a promise that a physical temperature is achievable. Demand is 50% at the selected temperature and increases linearly with temperature error, clamped to 0–100%. The full response bands are 20°C for chip, 10°C for Trackpad/Actuator and 16°C for Airflow. These are initial response choices rather than new hardware-critical thresholds or calibrated thermal guarantees. Ambient temperature and workload can prevent reaching a goal.

Final demand remains the maximum of target, enabled curves, floor and immutable chip guard. A target cannot weaken an existing curve or chip safety. Existing demand hysteresis/rate limiting and independent per-fan RPM limits apply. No Apple fan-floor behavior is claimed.

Target inputs extend the profile's required sensor set even when its ordinary curve is disabled. Sensor qualification, complete fresh acquisition, helper eligibility and root-side chip escalation remain required. Missing, stale, corrupt or unqualified required readings block control or request System. Preview explicitly reports its target request and remains non-authoritative.

Targets are optional profile metadata, preserved by duplication, local persistence, complete settings interchange and individual scheduled-profile interchange. Old profiles decode without a target. Imports reject unexpected nested target fields and malformed/nonfinite targets. Targets never carry hardware qualification or a runtime lease.

## Rename

The profile header shows a labeled Rename button with a pencil icon. Sidebar secondary-click opens a native Rename menu for that exact row. Both open a focused name dialog, with Cancel/Rename and validation. System/Max show disabled rename actions; the other built-ins may be renamed while retaining their stable identifiers and reset capability.

Rename is undoable. Changing an active profile's name updates presentation metadata without incrementing generation, restarting its lease or changing the cooling policy. The metadata-only operation validates that every field except the name is identical; it rejects attempts to use the path for target/curve changes. Schedules and activation defaults refer to stable IDs and survive renaming.

## Verification

314 Swift tests (28 hardware, 190 core, 96 app), 33 tool tests, full Address Sanitizer (leak detection disabled) and signed single-job build pass. Added cases cover target interpolation/bands/clamps, numeric rejection, maximum-demand composition, complete/qualified input requirements, sensor failure/staleness handback, backward decoding, all interchange paths, hostile target fields, protected modes, native rename menu state and name-only lease continuity/undo.

No screenshots, automated GUI navigation or synthetic workloads. Actual comfort/thermal accuracy remains a human calibration follow-up; an unattainable target is not treated as proof of a sensor failure. The hardware command sequence, five-method authenticated helper interface, watchdog, System-first startup/wake and qualified hardware limits are unchanged.

Installed through verified both-fan automatic release, unregister/service absence, signature-verified replacement and normal ServiceManagement registration. Startup check passed five ticks in System, helper controlReady, modes 0/0 and no monitoring warning. Signing identity, profiles and login registration are preserved. The delivered app starts in System; targets are opt-in and no new hardware target experiment was run.
