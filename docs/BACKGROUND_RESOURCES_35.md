# Background controller resource work — local build 35

This pass measures closed-UI background control, including steady held fan demand
and continuously changing targets. It does not use menu-rendering improvements as
evidence of background savings. The requested 2× CPU and 2× memory targets remain
acceptance goals, not achieved claims.

## Changes

- Reuse the current native registration observation within a polling iteration.
  Native registration is still checked on each iteration and profile selection;
  authenticated connection health remains a separate requirement.
- Bound native temporary-object lifetimes during polling, process-catalog reads,
  JSON wire encoding/decoding, diagnostic work items and closed-window teardown.
  Returned payloads and complete hardware readings remain owned after pool drain.
- Treat an unchanged, previously acknowledged direct-interface target request as
  a read-only heartbeat. Every request still gets fresh complete required inputs,
  a fresh exclusive-controller scan, normalization, live-lease validation and
  independent mode, target, metadata and bounds verification. Reference adapters
  and qualification continue through their existing physical transaction paths.
- Keep cancellation/deadline checks in the read-only verifier without repeating
  write-admission process scans inside that operation. This verifier has no write
  transport. Changed targets retain fresh checks at each write boundary; adjacent
  duplicate checks with no intervening operation were removed.
- Let a complete command observation satisfy the immediately overlapping watchdog
  observation interval. Its timestamp is acquisition start, not late completion.
  Expiry decisions still run independently every 100 ms; the existing 500 ms
  observation interval remains. Repeated commands still detect stopped fans.
- Publish completed observations rather than manufacturing an additional sensor
  acquisition just to refresh status. Cached health still becomes stale when
  hardware work stops progressing. Recovery and idle publication remain active.
- Add fixed-size, passive thread-CPU counters for sampling, SMC transactions,
  controller scans and status encoding, plus each process's own physical footprint
  and CPU totals. These fields do not authorize commands or accept caller timing.
  Sampling includes SMC work, so phase totals must not be added together.

Cooling curves, automation, deadlines, input membership, ownership checks,
authenticated hardware writes and automatic restoration are preserved. A dead or
blocked helper still cannot execute its watchdog.

## Measurement method

The original build 34 source was archived before these changes. Measurement-only
instrumentation added the same fixed workloads and output encoding to that copy;
it used the original installed build 34 helper. The candidate uses the canonical
notarized build 35 app and helper installed through ServiceManagement replacement.
User profiles and automation were compared during installation and preserved.

The fixed workloads use the ordinary app model, profile engine, XPC client and
helper, with isolated configuration and all menus/windows closed:

- Steady: ten minutes holding a quiet 3% normalized request after admission warmup.
- Changing: three minutes alternating quiet 3%/4% requests on successive ticks.

These are controller benchmarks, not benchmarks of editor rendering or the full
user's ordinary workload. The diagnostic entry point omits the normal updater and
shortcut loop. Native process CPU-time deltas and physical footprint are collected
separately; resident memory is not substituted for physical footprint. Root helper
footprint is available through `top`; the new helper also publishes its own counters.

No synthetic heat stimulus, loud profile, forced sleep, power-setting change or
screen capture was used. Initial changing-demand windows hit the conservative
75°C diagnostic ceiling during compilation and restored macOS ownership; those
windows are excluded. Compilation and accepted live sessions are kept separate.
Sleeping, failed and disconnected windows are not counted as resource gains.

The first candidate's changing-target comparison showed little combined CPU gain.
Passive phase measurements identified process scans as its main cost. The final
revision removed duplicated checks while keeping fresh admission and write checks.
That intermediate result is not substituted for the final revision's measurement.

## Verification

Tests preceded behavior changes. Local red logs include actual retained temporary
objects, redundant reads/checks and a write-admission requirement on the read-only
verifier. Missing-API failures are distinguished from runtime assertion failures.
Existing safety regressions caught early versions that skipped normalization or
changed first-admission watchdog timing; production code was corrected, with those
assertions retained.

Coverage includes unchanged/changing targets, adapter rounding, changed metadata
and ownership, fresh controller admission, cancellation, partial failures, sensor
loss, stopped fans despite frequent heartbeats, bounded observation coalescing,
native object lifetime, legacy optional-field decoding and the 16 KB wire limit.

The full Swift suites passed 596 tests; 65 tool tests, 23 focused
AddressSanitizer tests and six focused ThreadSanitizer tests passed. The arm64
Release build was signed, notarized and installed locally with the existing
configuration preserved. No public release was made.

## Steady background results

On the available M5 Pro, the ten-minute steady sessions yielded a median app
physical footprint of 17.61 MiB before and 17.88 MiB after. App CPU was 0.265%
and 0.258% of one core respectively, effectively unchanged in these windows.
The final helper's median footprint was 5.44 MiB. In separate approximately
90-second process windows, helper CPU fell from 3.03% to 1.80% of one core,
approximately 40%. The full candidate helper window averaged 1.92%.

The 2× goals were not reached. In a private experiment, one allocator trim
after warmup changed the measured footprint by zero bytes immediately; it was
not added to production. An allocation snapshot showed about 5.5 MiB of live
heap and substantial allocator fragmentation, which cannot simply be counted
as reclaimable memory. These results do not establish a reduction after a user
has opened and closed the editor.

## Changing background results

In matched approximately 85-second process windows during the three-minute
changing-demand sessions, combined app and helper CPU was 4.90% of one core
before and 4.83% afterward. Combined median physical footprint was 22.74 MiB
before and 22.55 MiB afterward. These small differences do not establish a
meaningful improvement. Both complete sessions held manual ownership with the
requested quiet targets and returned control to macOS afterward. An independent
read confirmed automatic mode on both fans after the final session.

The full final steady and changing sessions collected 567 and 150 observations,
respectively. The installed candidate is version 0.3.3 build 35; the notarized
DMG and private measurements are kept locally. The normal app was left closed
after testing, preserving the user's saved profile selection.

## Remaining work toward the targets

Memory must be assessed independently of CPU. This pass does not establish a 2×
memory reduction. Prior UI use can leave framework and allocator residency after
the view graphs themselves have been released; a cold controller diagnostic does
not establish the footprint of that already-used application.

Further memory work needs matched background lifetime measurements after ordinary
editor use, separating live ownership, allocator reservation and loaded framework
caches. An on-demand presentation boundary is a possible architectural experiment,
but must preserve drafts, undo, automation, immediate activation and single-owner
control. It has not been implemented or claimed as a proven memory solution here.

The remaining helper CPU cost includes actual SMC acquisitions and fresh native
controller scans. Their cadence and scan coverage were not reduced to reach a
benchmark target. Physical tests here cover the available M5 Pro only.
