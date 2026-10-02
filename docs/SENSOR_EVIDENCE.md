# Sensor candidates and required evidence

The signed production policy reviews a fixed 105-key chip envelope and five operational chassis inputs on Mac17,9. CPU/GPU physical membership and informational proximity identities remain pending. Top is explicitly labelled as a proximity proxy, not certified as the exact TG Pro Airflow Top sensor. See [the composite review and targeted result](TEMPERATURE_PROFILE_STATUS.md). The public repository contains candidate mappings and reproducible analysis tools, but excludes raw recordings, reference CSV files and operator-specific measurements. Normal operation reads hardware independently; TG Pro is a development reference only.

| Role | Candidate / source | Required review |
| --- | --- | --- |
| CPU average / peak | Explicit 23 Tp / 40 Tm informational manifest; published Stats anchors | Active membership, averaging semantics and reliable hottest-core coverage. Wider unselected Tp/Tm readings must be explained. |
| GPU average / peak | Published Stats M5 GPU group; absent members recorded separately | Exact-model region membership and peak coverage; unselected Tg readings and acquisition lag. |
| Trackpad | Ts0P; historical VirtualSMC name | Reviewed composite comfort evidence; physical surface accuracy is not asserted. |
| Actuator | Ts1P; historical VirtualSMC name | Reviewed; separate scale and documented competing candidates. |
| Airflow Left | TaLP; Stats name | Reviewed source/typed acquisition/reference/response evidence. |
| Top proximity (internal airflow-group member) | TaTP; independent Ambient Top Proximity provenance, typed model observations, paired range and chassis response | Reviewed operational proxy on the airflow scale. Exact TG Pro Airflow Top identity is unproved; no equivalence claim. |
| Airflow Right | TaRF; Stats name | Reviewed source/typed acquisition/reference/response evidence. |
| Charger Proximity | TCHP; historical VirtualSMC name | Model-sensitive conflicts and corroboration. Charging alone must not drive aggressive comfort cooling. |
| Power Supply Proximity | TPSP; iSMC broad-platform candidate | Exact-model identity and competing interpretations. |
| Wireless Proximity | TW0P; historical wireless / Stats Airport name | Current-model corroboration and timing agreement. |

Every requested role remains a discovery goal, including all three proximity sensors. The user revised delivery to qualify only the sensors needed by each control policy; proximity readings may remain informational. The production gate is now split: fixed Max does not need temperature identities, while curve profiles require their own verified roles. A separately authorized finite mechanical recovery test uses candidate read health and a wider diagnostic guard without qualifying any identity; see [its scope](MANUAL_QUALIFICATION.md). Discovery requirements do not make proximity sensors independent comfort-demand drivers. Chassis control uses separate Trackpad, Actuator and Airflow scales, then maximum demand; stronger chip cooling always wins.

Evidence records provenance, type, acquisition timing, competing candidates, aliases and uncertainty. Similar temperatures or correlation alone do not establish identity. Missing/invalid members cannot become zero or silently disappear from an aggregate. Broad-platform tables are candidates, not exact-model qualification certificates.

Offline prefix-family audits reveal possible omissions; they do not automatically grant authority. Production uses the reviewed fixed manifest, never runtime prefix enumeration or opportunistic membership. Equal numeric traces establish redundancy in that recording, not physical identity. Sequential acquisition, reference rounding and timing lag can explain transient differences.

Raw data and detailed reports remain local. Review [hardware gates](HARDWARE_GATES.md), [research provenance](RESEARCH.md) and [third-party notices](../THIRD_PARTY_NOTICES.md) before changing compiled qualification evidence.

## Current source check

The current [Stats M5 definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) retain the published Tp/Tg candidates. [ThermalForge’s Mac17,9 compatibility report](https://github.com/ProducerGuy/ThermalForge/issues/26) reports Max/Auto operation but does not settle the local Tm-domain, missing GPU-member or comfort-label questions. Neither is new exact-model identity/coverage proof. At that source check no evidence flag changed; the later operational envelope/five-role composite review is linked above. System/Max qualification is mechanical and independent of these unresolved labels.

## Production control distinction

The separately named Chip envelope takes a complete fixed maximum across 105 observed Tp/Tm/Tg keys. It qualifies no individual CPU/GPU average or peak identity. Five operational chassis inputs retain separate scales; missing members fail the active policy. All temperature profiles are enabled after actual bounded recovery tests. See [delivery](TEMPERATURE_PROFILE_STATUS.md).
