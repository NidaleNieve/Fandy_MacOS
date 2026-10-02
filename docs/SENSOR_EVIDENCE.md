# Sensor candidates and required evidence

Four comfort identities are reviewed on Mac17,9: Trackpad, Actuator, Airflow Left/Right. Chip coverage, Top semantics and informational proximity mappings remain pending. See [the composite review and targeted result](TEMPERATURE_PROFILE_STATUS.md). The public repository contains candidate mappings and reproducible analysis tools, but excludes raw recordings, reference CSV files and operator-specific measurements. Normal operation reads hardware independently; TG Pro is a development reference only.

| Role | Candidate / source | Required review |
| --- | --- | --- |
| CPU average / peak | Explicit 23 Tp / 40 Tm informational manifest; published Stats anchors | Active membership, averaging semantics and reliable hottest-core coverage. Wider unselected Tp/Tm readings must be explained. |
| GPU average / peak | Published Stats M5 GPU group; absent members recorded separately | Exact-model region membership and peak coverage; unselected Tg readings and acquisition lag. |
| Trackpad | Ts0P; historical VirtualSMC name | Reviewed composite comfort evidence; physical surface accuracy is not asserted. |
| Actuator | Ts1P; historical VirtualSMC name | Reviewed; separate scale and documented competing candidates. |
| Airflow Left | TaLP; Stats name | Reviewed source/typed acquisition/reference/response evidence. |
| Airflow Top | TaTP; iSMC Apple Ambient Top Proximity candidate | Exact-model Airflow Top identity. Ambient and Airflow descriptions cannot be assumed equivalent. |
| Airflow Right | TaRF; Stats name | Reviewed source/typed acquisition/reference/response evidence. |
| Charger Proximity | TCHP; historical VirtualSMC name | Model-sensitive conflicts and corroboration. Charging alone must not drive aggressive comfort cooling. |
| Power Supply Proximity | TPSP; iSMC broad-platform candidate | Exact-model identity and competing interpretations. |
| Wireless Proximity | TW0P; historical wireless / Stats Airport name | Current-model corroboration and timing agreement. |

Every requested role remains a discovery goal, including all three proximity sensors. The user revised delivery to qualify only the sensors needed by each control policy; proximity readings may remain informational. The production gate is now split: fixed Max does not need temperature identities, while curve profiles require their own verified roles. A separately authorized finite mechanical recovery test uses candidate read health and a wider diagnostic guard without qualifying any identity; see [its scope](MANUAL_QUALIFICATION.md). Discovery requirements do not make proximity sensors independent comfort-demand drivers. Chassis control uses separate Trackpad, Actuator and Airflow scales, then maximum demand; stronger chip cooling always wins.

Evidence records provenance, type, acquisition timing, competing candidates, aliases and uncertainty. Similar temperatures or correlation alone do not establish identity. Missing/invalid members cannot become zero or silently disappear from an aggregate. Broad-platform tables are candidates, not exact-model qualification certificates.

Offline prefix-family audits reveal possible omissions; production never adopts every prefix as a safety signal. Equal numeric traces establish redundancy in that recording, not physical identity. Sequential acquisition, reference rounding and timing lag can explain transient differences.

Raw data and detailed reports remain local. Review [hardware gates](HARDWARE_GATES.md), [research provenance](RESEARCH.md) and [third-party notices](../THIRD_PARTY_NOTICES.md) before changing compiled qualification evidence.

## Current source check

The current [Stats M5 definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) retain the published Tp/Tg candidates. [ThermalForge’s Mac17,9 compatibility report](https://github.com/ProducerGuy/ThermalForge/issues/26) reports Max/Auto operation but does not settle the local Tm-domain, missing GPU-member or comfort-label questions. Neither is new exact-model identity/coverage proof. At that source check no evidence flag changed; the later four-role composite review is linked above. System/Max qualification is mechanical and independent of these unresolved labels.
