# Temperature-profile delivery — 2026-10-02

The production registry now selects `qualifiedControl` on Mac17,9. System+, Gaming, Cool Chassis, School and custom curves use real independently acquired temperatures. System and Max remain protected. This supersedes the earlier maximum-only and inactive-envelope checkpoints.

## Control inputs

Chip control uses the maximum of a fixed 105-key Tp/Tm/Tg manifest, separately named **Chip envelope**. Every member is mandatory, fresh, correctly typed and finite. CPU/GPU averages remain informational estimates; their exact physical membership is not certified. Neither those estimates nor proximity candidates can substitute for a failed envelope. See [the policy and limitations](CHIP_ENVELOPE.md).

Five chassis inputs are reviewed operationally: Trackpad Ts0P, Actuator Ts1P, Left TaLP, Right TaRF and **Top proximity TaTP**. Top uses independent ambient-top provenance, complete typed model observations, 1156 paired reference readings across an 18°C range and slow chassis response. This is an explicit proximity proxy on the airflow scale, not a certification of TG Pro's exact Airflow Top identity. TRDd/TRDc remain numerical competitors. The UI uses the proxy's actual reviewed description. A missing Top member invalidates an enabled airflow curve; it is never silently dropped.

Trackpad/Actuator/Airflow retain independent temperature scales. Final demand is the maximum of enabled curves, profile floor and immutable chip guard. Charger, power supply and wireless remain informational candidates and never independently raise fan demand. Normal operation does not read the reference CSV or require TG Pro.

## Actual hardware fixes

- Automatic target preloading read back zero on this model. The reviewed production transaction establishes and verifies both manual modes before writing validated targets; it uses no unlock key, target clearing or alternative-write fallback.
- Warm re-entry can take approximately nine seconds before actual RPM is reported. Eight-second diagnostics incorrectly failed before spin-up. Bounded recovery observations now fit inside the existing nonrenewable fifteen-second qualification lease. Production retains its ten-second stalled-fan check.
- Firmware acknowledged a fractional request of 2867.9 as 2867 RPM. The helper now rounds upward to whole RPM within separately verified integral fan bounds, for both profile requests and independent thermal escalation. Ownership tracking uses those normalized targets. Curve interpolation remains continuous.
- Every admitted controller update refreshes its validated SMC target. The client reuses only an immediately issued observation (at most 250 ms old) to avoid duplicate status RPCs. The helper still reads and validates hardware independently before each write; message limits were not increased.

## Recovery evidence

Spinning re-entry and subsequent target updates passed with actual RPM, followed by both mode-0 handbacks. Heartbeat expiry restored both fans at approximately 10.51 seconds; owned disconnect at approximately 1.04 seconds; the nonrenewable deadline at approximately 15.14 seconds. Controller SIGKILL after observed rotation returned both modes to automatic in 0.17 seconds. Normal termination from a variable-speed lease verified both automatic modes. Prior measured helper restart recovery is retained because startup restoration is unchanged.

The original modest five-second trial and System/Max mechanical qualification remain valid. The former qualification authority is disabled in the production stage; callers cannot choose trial duration or unlock production by preferences/XPC. A dead or blocked helper still cannot execute its own watchdog.

Initial temperature-delivery verification: 189 Swift tests (28 hardware, 134 core, 27 app), 31 Python tool tests, a single-job signed build and strict nested signature verification. Active curve editing preserved manual ownership; simulation-to-hardware reactivation and paced rapid-switch/System checks also passed. Actual production profile and calibration results are recorded in [delivery status](DEVELOPMENT_STATUS.md).

## Follow-ups

Physical sleep/wake with active ownership still needs an observed hardware test; both process state machines and the native notification handling are implemented and model-tested. Subjective comfort/noise feedback and sustained gaming calibration remain separate follow-ups. Exact CPU/GPU identities and the three informational proximity labels remain research goals rather than gates for the explicitly reviewed operational policy.

## Earlier sensor evidence

The following bounded measurements and source reviews are retained as evidence history. Their unresolved physical identities are not relabelled as proven by the operational policy.

## Bounded read-only result

The single approved 660-second session completed with 581 records and both fans in automatic mode throughout. It recorded 113 selected keys and named vendor-temperature HID events. Catalog enumeration occurred once before the baseline. Maximum selected-key acquisition span was 0.033 seconds.

| Candidate domain | Keys | Pre-pulse peak median | Pulse maximum | Rise |
| --- | ---: | ---: | ---: | ---: |
| Tp | 23 | 46.20°C | 61.19°C | 14.99°C |
| Tm | 40 | 43.61°C | 56.47°C | 12.86°C |
| Tg | 42 | 38.88°C | 39.25°C | 0.38°C |

The CPU response supports investigating both observed families; it does not resolve the Tm CPU/memory naming conflict or establish core membership. The GPU pulse supplied insufficient independent variation. Named PMU die readings were not substituted for CPU/GPU identity or coverage. No repeated session was run. Initial build activity overlapped part of baseline; the response comparison uses the final ten baseline samples, not the initial compilation peak.

The reference CSV contained no contemporaneous rows for this session. Its earlier 1156 paired readings remain separate evidence. New records are not falsely paired with old timestamps. The reporting tool changes no qualification; compiled mapping decisions below are a separate review.

## Mapping review

| Role | Result / basis |
| --- | --- |
| Trackpad, Ts0P | Reviewed for operational comfort use. Independent historical Trackpad/palm-rest naming, stable flt4 acquisition, 1156 contemporaneous pairs with 0.300°C mean error and 10°C reference variation, and separate slow chassis response distinguish this from chip demand. Battery-key numerical competitors remain documented. This is not a direct measurement of skin temperature. |
| Actuator, Ts1P | Reviewed for comfort use. Independent historical actuator naming, 1156 pairs with 0.241°C mean error across 9°C variation; next candidate's mean error is 0.710°C farther away. Separate scale and slow response retained. |
| Airflow Left, TaLP | Reviewed for comfort use. Independent Apple Silicon Left naming, complete flt4 observations, 1156 pairs with 0.275°C mean error across 17°C variation, and airflow response distinct from Trackpad/Actuator. Common thermal movement among competitors is not treated as an alias. |
| Airflow Right, TaRF | Reviewed for comfort use. Independent Apple Silicon Right naming, complete flt4 observations, 1156 pairs with 0.253°C mean error across 18°C variation, and the distinct airflow temperature scale. Wireless numerical competition remains explicit. |
| Airflow Top, TaTP | Pending: Ambient Top Proximity provenance does not independently establish the Airflow Top label. No nearest-temperature replacement. |
| CPU average/peak | Pending: both observed clusters must be represented by a reviewed membership set, with the Tm memory/CPU source conflict resolved. No guessed core numbering. |
| GPU average/peak | Pending: reviewed regional coverage, absent published member and hotter unselected candidates remain unresolved; the new pulse did not discriminate them. |
| Charger, Power Supply, Wireless | Pending informational mappings. They do not gate profiles that do not use them. |

Published naming references: [VirtualSMC keys](https://github.com/acidanthera/VirtualSMC/blob/master/Docs/SMCSensorKeys.txt), [Stats sensor definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift), [iSMC descriptors](https://github.com/dkorunic/iSMC/blob/master/smc/sensors.go). Existing license notices remain; no implementation or proprietary mapping table was copied.

The later native-polish pass passed 200 Swift tests and 31 tool tests, plus a refreshed signed live profile/editor check. Invalid draft retention/correction, active editing, backend switching and System handback passed; the physical writer and watchdog were unchanged. See [delivery status](DEVELOPMENT_STATUS.md).
