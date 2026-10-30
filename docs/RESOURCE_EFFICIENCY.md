# Resource efficiency — local candidate 33

The follow-up [background-resource report](BACKGROUND_RESOURCES.md) covers local
build 34. Its controlled menu footprint improved, but the requested 2× memory and
additional 2× active-control CPU targets remain unmet. The build-33 System result
below must not be generalized to that newer workload.

The target is at least 50% lower combined app/helper CPU cost during comparable
ordinary-use monitoring. CPU, resident memory, wakeups and latency are separate
metrics; a CPU reduction is not a claim of twice the battery life or half the memory.

## Changes

- The status item observes relevant model changes and applies only changed title,
  tooltip and accessibility presentation. It no longer redraws on a one-second timer.
- Idle helper monitoring follows the one-second GUI cadence, with timer leeway.
  Active leases, recovery trials and failed-restoration retries retain the original
  100 ms timer and active watchdog observations remain twice per second.
- Status publication can reuse a just-validated acquisition for at most 250 ms.
  Commands and admission always acquire fresh data. Reuse cannot renew a heartbeat,
  advance healthy-acquisition counts or survive restoration, failure or sleep reset.
- Advisory controller presence can reuse a recent result; every admission, command
  and active watchdog still checks it freshly. The hardware writers retain their
  independent controller checks.
- Fixed selected-key membership and qualified-role sets are prepared once. Every
  snapshot still reads every selected member; readings and write metadata are not cached.
- The direct adapter skips identical target writes only for already-manual fans,
  after validating all modes/target metadata. Admission still writes each fan's target
  promptly after its mode acknowledgement; final readbacks and deadlines remain.

## Verification method

Tests were added before production changes. Initial missing-API regressions and a
runtime failure using the original direct writer are retained in private local logs.
The complete suite passed 554 Swift tests and 63 tool tests. Focused AddressSanitizer
and ThreadSanitizer checks passed; actual helper timer transitions were exercised with
injected production bootstrap, including failed restoration retaining fast retries.

On the available M5 Pro, sample process CPU-time deltas and resident memory every
five seconds for three minutes, with the installed app and helper in awake System
monitoring. Use identical settings and successful monitoring records to check that
sleep or disconnection did not manufacture a lower number. Native measurements and
user configuration remain ignored, local files. Benchmarks cannot certify other Macs.

The original helper was suspended on initial inspection; that observation was excluded.
Normal LaunchServices startup restored its registration after a CLI registration
refusal. Local candidate installation used normal launch, retained approval, and
preserved profile/automation/preference data. Both fans were automatic before sampling.

Final measurements and limitations are recorded below after the matched comparison.

References: [Apple timer guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)
and [dispatch timer leeway](https://developer.apple.com/documentation/dispatch/dispatch_source_set_timer).

The first optimized sampling window resumed Cool Chassis while the baseline was
System. It was excluded from the before/after result rather than treating different
workloads as a performance regression or improvement. Its raw data is retained locally.

## Measured result — M5 Pro, 2026-10-29

Two matched ordinary-use System/monitoring windows sampled the actual signed Release
app and privileged helper every five seconds. Measured spans were approximately
175 seconds each. Both had 35 successful live monitoring records with automatic fan
modes and no recording gap above six seconds. The excluded active-profile window
was not used to calculate these improvements.

| Metric | Baseline build 32 | Local build 33 |
| --- | ---: | ---: |
| App CPU, one-core scale | 0.872% | 0.143% |
| Helper CPU, one-core scale | 1.578% | 0.964% |
| Combined CPU | 2.450% | 1.106% |
| Combined median resident memory | 92.4 MiB | 83.5 MiB |

Combined CPU cost was 54.9% lower: a 2.22× efficiency factor for this workload.
Resident memory was approximately 9.6% lower, not halved. Idle helper timer policy
changed from ten firings per second to one, while active timing remains unchanged;
this is a scheduling count, not a measured 90% reduction in all kernel wakeups.

Cool Chassis ran successfully on the candidate with acknowledged manual modes on
both fans. Its CPU cost is retained separately; no matched original active-control
window was collected, so the System result must not be generalized to active cooling,
other Macs, UI editing or battery life. Repeat longer measurements under comparable
ordinary use before making broader claims. Configured curves, targets, smoothing,
schedules, expiry rules, permissions and thermal-pressure handback were preserved.


## Native acceptance

The notarized Developer ID candidate is installed locally as 0.3.3 build 33. The
public release was not changed. Profiles, automation and preferences matched the
pre-install configuration. Cool Chassis held both fans in manual control during the
separate active observation. The subsequent System request recorded manual-to-
automatic transitions on both fans, with immediate and final readbacks verified.

After the matched measurements, the native latency check passed: p95 acquisition
26.2 ms, status 1.54 ms, monitoring tick 32.1 ms and main-actor dispatch 1.50 ms. Native
malformed/oversized requests, forged authority/targets, obsolete qualification and
wrong helper identity were rejected. The separate quiet quit-recovery trial skipped
because no upward margin was available with stopped fans; it is not counted as a pass.
No Max, Gaming, synthetic heat workload or forced sleep session was run.

Limitations: this is a short ordinary-use comparison on one M5 Pro. Memory remains
largely framework/UI residency, and CPU results vary with model, OS, active inputs,
UI usage and workloads. Active cooling has the unchanged watchdog and command
freshness checks; its 2× CPU target remains unmeasured against the original build.
