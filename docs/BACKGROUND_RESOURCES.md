# Background resource use — local build 34

Subsequent closed-UI controller work is recorded in
[the build 35 report](BACKGROUND_RESOURCES_35.md). The measurements below remain
the historical build 34 results.

## Result and acceptance

This pass reduces retained UI memory while preserving monitoring, profiles,
automation and recovery behavior. **The requested 2× memory and additional 2× CPU
targets have not been achieved.** The 4× memory aspiration is also unmet.

The controlled menu lifecycle check measured approximately **35% lower physical
footprint**. The matched quiet-control CPU windows were effectively unchanged.
Opening the full editor still leaves substantial framework residency after close.
Do not describe this build as halving memory, doubling active-control efficiency,
or improving battery life by a measured amount.

The signed, notarized local candidate is **0.3.3 build 34**. It is installed locally;
the public release and updater feed have not changed.

## Implementation

- Native AppKit starts the background application. SwiftUI's application-level
  Settings scene is no longer initialized just to run the controller. Standard
  Settings, text-editing and profile undo commands remain available.
- The main menu's fan and temperature readouts use native labels and the existing
  compact bar. Preferences, aligned temperature columns and accessibility labels
  remain. Time and application pickers materialize when their submenu is opened.
- Closing the menu releases its embedded controls. Cleanup is deferred outside
  tracking, preserves pending native actions and cannot erase a reopened menu.
- Closing Profiles or Settings discards hosting content and nested view graphs.
  Native window geometry and resized sidebar positions remain. Profile edits,
  selection, undo history, the editor tab and cached curve field drafts live outside
  the discarded graph. Drafts are invalidated when their source curve changes.
- One coalesced allocator trim after UI closure returns already-freed pages to
  macOS. It does not evict live objects or run on an ongoing idle timer. Framework
  caches that remain allocated cannot be reclaimed through this mechanism.
- Successfully validated capability reports are reused only when both the report
  and complete capabilities are identical. Changes are revalidated; failures clear
  that cache. Readings, leases and failed resolutions are not cached there.
- Fan inventory uses the freshly decoded mode instead of immediately reading that
  same mode twice. It does not cache mode values or mode metadata between samples.
- A synchronous target transaction reuses its complete preflight inventory rather
  than enumerating it again at each software layer. Write metadata remains fresh.
  One subsequent inventory verifies both target acknowledgements, modes and bounds.
  Polling remains bounded and cancellable; failures restore every fan. The reference
  handover sequence is unchanged.

Sensor cadence, target evaluation cadence, heartbeat expiry, active watchdog
timing, configured cooling curves and thermal-pressure handback were retained.

## Measurements on the available M5 Pro

### Native UI lifecycle fixture

An isolated copy of build 33 was compiled with measurement-only instrumentation.
The original implementation and candidate ran the same three offscreen native menu
open/close cycles on this Mac. The fixture uses simulated readings, no hardware
commands, no screenshots and no automated GUI navigation. Footprint comes from
`TASK_VM_INFO.phys_footprint`; it is distinct from resident size and peak memory.

| Physical footprint | Original build 33 | Final build 34 |
| --- | ---: | ---: |
| Cold diagnostic process | 19.59 MiB | 15.38 MiB |
| After three closed menu cycles | 25.09 MiB | 16.28 MiB |

Menu-cycle footprint was 35.1% lower, a **1.54×** factor. The candidate's extended
fixture, which also opened and closed Profiles and Settings three times, settled
at approximately **48.70 MiB**. No matched original editor fixture was collected;
the original menu-only result must not be used as its editor baseline.

An earlier observation of the already-used original app showed an 82.7 MiB
footprint and 165.8 MiB peak. That was not the same controlled workflow and is not
used to claim a 2× improvement. The UI fixture is also not a measurement of the
complete awake controller plus privileged helper under every profile.

The exact notarized installation also had a **17.4 MiB** app footprint in an awake
System snapshot with fresh helper readings and independently automatic fan modes.
The original app's stabilized System snapshot was 31.2 MiB, but these are individual
observations rather than matched long-duration memory distributions. They do not
establish a universal 2× reduction or the footprint after subsequent editor use.

### Ordinary-use quiet control

Both builds ran the existing fixed Cool Chassis diagnostic with the normal GUI
closed, user configuration isolated, fresh real sensors and both fans in manual
control. Process CPU-time deltas and resident size were sampled every five seconds
for approximately 175 seconds. No heat stimulus or loud profile was used.

| Metric | Build 33 | Build 34 |
| --- | ---: | ---: |
| Combined app/helper CPU, one-core scale | 3.528% | 3.569% |
| Combined median resident size | 84.73 MiB | 81.69 MiB |

The approximately 1.2% relative CPU increase is a small difference in short
ordinary-use windows, not evidence of a meaningful improvement or regression.
Temperatures and targets varied between sessions. The resident-size change was
approximately 3.6%; it must not be substituted for the separate footprint result.

Initial installed latency checks occurred during maintenance sleep/DarkWake and
were rejected because the helper correctly withheld live readings. No sleeping or
disconnected samples were counted as resource improvements. After an explicit
user wake, native checks passed: p95 acquisition 23.8 ms, helper status 0.99 ms,
monitoring tick 30.2 ms and main-actor dispatch 3.59 ms.

## Verification and installation

Regression tests preceded production changes. Missing-API regressions and intended
runtime failures, including retained closed views, duplicate mode reads and repeated
inventories, are recorded in ignored local logs. A test that formerly depended on
SwiftUI creating `NSApplication` now initializes the native application explicitly;
its context-action assertions were retained.

- Complete Swift suites: **573 passing tests**.
- Tool suite: **63 passing tests**.
- Focused AddressSanitizer: **16 passing tests**.
- Focused ThreadSanitizer: **5 passing tests**.
- One-job arm64 Release build and native functional startup check passed.
- Native malformed/oversized requests, forged authority/targets, wrong protocol,
  stale generations and incorrect helper identity were rejected.
- Quiet control held both fans; normal quit recorded **manual → automatic** on
  each fan. Independent SMC reads confirmed both automatic modes afterward.

The existing saved notarization profile initially appeared unavailable while the
Mac was asleep/locked. It worked after unlock; no credentials were recreated.
Separately signing equivalent bundles produced different outer code hashes, so the
canonical notarized DMG payload was installed through verified handback and normal
ServiceManagement replacement. A ticket from a different bundle hash was not applied.
Profiles, automation and preferences were verified unchanged during installation.

This is local M5 testing. It does not certify inaccessible M1–M4 hardware. Raw
measurements, user configuration, power logs and signing information remain local
and ignored by Git.

## Work still required for the targets

1. Profile remaining private allocations on an awake Mac after ordinary editor
   use, separating live graphs, allocator reservation and framework caches. Tests
   now establish that outer and nested editor controllers are actually released.
2. If framework residency remains the floor, evaluate an on-demand UI process or
   module boundary. Preserve a single controller owner, immediate profile actions,
   draft/undo state, schedules and deadlines; restarting the controller or dropping
   monitoring is not an acceptable substitute for memory optimization.
3. Instrument helper phase CPU, including SMC transport and repeated known-controller
   scans, then benchmark unchanged and changing targets separately. Fewer inventory
   reads did not translate into the requested overall CPU reduction in this run.
4. Repeat matched awake measurements after each justified change. Retain complete
   readings and recovery timing; do not manufacture gains through sleep, App Nap,
   forced paging or reduced functionality.
