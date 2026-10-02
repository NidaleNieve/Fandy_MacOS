# Temperature-profile checkpoint — 2026-10-02

Latest continuation: [a separate conservative chip-envelope path](CHIP_ENVELOPE.md) is implemented and tested but inactive, pending the user's policy decision. A new 180-second render recording has 146 contemporaneous TG Pro pairs; GPU variation remained insufficient to qualify individual regions. The current build still grants only System/Max. This supersedes the earlier statement that the reference log has no new rows; that statement remains true for the earlier 660-second session.

System and Max remain operational. Temperature profiles are **not enabled**: the bounded measurement did not resolve CPU membership and GPU coverage sufficiently. No temperature-control experiment or simulated success was used to bypass that result. A final regression of the already-qualified Max/System path passed actual maximum RPM and both-fan automatic handback.

## Implemented

The model-specific registry now supports independent average/maximum groups. Each SMC reading carries its monotonic completion time; a group uses its earliest member time so a long acquisition cannot make old data appear fresh. Missing, corrupt, nonfinite or wrongly typed members invalidate the entire group. Older discovery records decode without the optional timing field; they cannot masquerade as newly acquired control readings.

The CPU informational envelope explicitly includes the 23 observed Tp and 40 Tm candidates. Both families responded to the separate CPU pulse. This is a fixed current-model candidate manifest, not a runtime prefix-based control rule or a claim that every member is a CPU core. CPU averages remain candidate sensor averages, not verified per-core averages. GPU informational membership remains the seven present published candidates; absent Tg1g is documented rather than silently removed during acquisition.

A signed `curveQualification` stage is implemented and tested but **not selected in the delivered build**. Ordinary temperature profiles remain unavailable in that stage. Required verified sensor roles are still mandatory. Root-owned curve trials have a nonrenewable 15-second deadline, upward-only admission floors of max(observed RPM, spinning minimum) + 200 per fan, and the existing ten-second heartbeat timeout. A late batch is rejected before its two-second physical transaction budget would cross the deadline. The deadline is checked again after I/O; blocked kernel I/O remains the documented limitation.

The XPC interface remains five methods. Optional lease expiry preserves older reply decoding; requests cannot supply expiry or qualification authority. Fixed curve check/heartbeat/disconnect/hold diagnostic flags accept no RPM, keys, duration or profile parameters and reject the current maximum-only build before issuing commands.

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

## Exact remaining work

1. Obtain a discriminating GPU-region recording during an ordinary game/render workload, with a contemporaneous temperature-only reference if available. Do not repeat this ineffective low-duty pulse. Normal Fandy operation must remain independent of the reference app, and competing fan control must remain stopped.
2. Resolve the Tm region membership using independently attributable current-model descriptions or evidence that distinguishes CPU regions from memory. A rapid thermal response alone cannot assign a physical identity.
3. Review Top proximity versus Airflow Top semantics. Keep only this dependent comfort role pending; do not reopen the four completed comfort reviews without conflicting evidence.
4. Once chip roles pass, install the bounded qualification build, run the fixed upward curve check and recovery cases, then enable System+/Gaming and chip-only custom profiles. Comfort profiles follow their final Top review.
5. Physical sleep/wake, automatic-at-idle release/re-entry, rapid production curve switching and System/System+/Cool Chassis calibration still require the enabled curve path. These were not falsely marked passed by Max tests.

The signed native build passes 169 Swift tests (24 hardware, 122 core, 23 app) and 30 Python tests. Installed functional monitoring passed with control-ready helper health, System state and both automatic fan modes. The inactive curve diagnostic was rejected. Strict deep signature verification passed.

Delivered authority remains `maximumControl`. Four of twelve requested roles are reviewed; every temperature policy requires the unresolved CPU/GPU safety roles. The application is left in System. Raw recordings, the reference CSV, local signing configuration and private handoff stay outside Git.
