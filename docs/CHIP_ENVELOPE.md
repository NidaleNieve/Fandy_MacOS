# Conservative chip-envelope integration

This operational policy is active in the signed production registry on Mac17,9 after bounded variable-speed recovery verification. It changes the control input instead of claiming unresolved physical identities are proven. Neither preferences nor XPC requests can select another policy.

## Meaning

The control input is the maximum across a fixed, model-specific manifest of 105 observed temperature keys: 23 Tp, 40 Tm and 42 Tg. It includes published CPU/GPU anchors and the additional regions observed in the exact-model recordings. The signed registry lists every member; production does not discover membership by a prefix or silently omit a missing member. Published Tg1g is absent on this machine and is recorded as absent model metadata.

This input is called **Chip envelope**, represented separately as `socPeak`. It does not qualify `cpuPeak`, `gpuPeak` or either average. Tm's CPU/memory naming conflict remains explicit; including a warmer memory-related region can increase cooling demand. The maximum is mathematically at least as high as each included subset. That is not a certification that every physical CPU/GPU hotspot is measured, nor proof that all members are CPU cores. CPU/GPU display values remain marked as candidates.

Both observed CPU candidate families rose during the earlier separate CPU pulse. Published chip naming, typed model observations, previous contemporaneous temperature-reference comparisons and that response form the operational basis. The additional GPU render recording does **not** supply sufficient independent GPU variation. This alternative changes the control policy rather than claiming that unresolved identities have become proven.

## Integration

`ChipControlPolicy` is carried by compiled hardware capabilities. Older capability replies decode to the original CPU/GPU policy; profile files and their curves are unchanged. Curve temperature evaluation, required-input calculation, eligibility, the state machine, freshness monitoring, client admission, helper target escalation and helper watchdog all use the same policy. The helper requires its compiled safety roles; callers cannot request a weaker policy.

Each envelope member must have a complete fresh acquisition, supported flt4 metadata and a finite plausible value. One failed member invalidates the envelope. There is no fallback to display estimates or partial maximum. Restoration still operates independently of sensor health. Chip guard demand continues to override edited or disabled chip curves.

Comfort profiles retain separate Trackpad/Actuator/Airflow scales. TaTP is explicitly reviewed and labelled as Top proximity, an operational proxy on the airflow scale, without certifying the exact TG Pro Airflow Top identity. It remains a mandatory member. The three other proximity values remain informational.

## New measurement

One finite 180-second automatic-mode session recorded 146 samples with 146 contemporaneous TG Pro matches. It used a 30-second baseline, 30 seconds of ordinary 4K Core Image blur/color processing at a bounded 24-frame/s cadence, and 120 seconds cooldown. It issued no fan writes. Both fans remained automatic; the maximum selected-key acquisition span was 0.079 seconds. GPU-region peak rise was only 0.266°C, so no individual GPU identity or coverage qualification was granted. No repeated load session followed.

The measurement tool stops on ownership loss, invalid/stale readings, serious/critical/unknown pressure, failed rendering or its 75°C diagnostic ceiling. That ceiling is a measurement limit, not an asserted Apple critical threshold. No image was displayed, inspected or saved; no screenshots or GUI automation were used.

## Actual recovery and delivery

Bounded upward variable targets, warm automatic re-entry, heartbeat expiry, disconnect, fifteen-second deadline, controller SIGKILL and normal termination passed with programmatic mode/RPM observations. Earlier helper restart evidence remains applicable because restoration on startup is unchanged. See [the complete checkpoint](TEMPERATURE_PROFILE_STATUS.md) for measured timings and the whole-RPM precision fix.

The production stage enables every built-in temperature profile and eligible custom curves. Startup and wake remain System-first. Native app-model profile tests and ordinary-use comparisons are recorded in [delivery status](DEVELOPMENT_STATUS.md). No CPU/GPU average or peak identity flag was promoted. Physical sleep/wake and subjective/game calibration remain follow-ups. A dead or blocked helper cannot run its watchdog.

189 Swift tests and 31 tool tests pass; the signed single-job native build and strict nested verification pass. Raw measurements and signing configuration stay local.
