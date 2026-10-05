# Timers, schedules and portable configuration — 2026-10-03

The subsequent [menu/profile delivery](MENU_POLISH_DELIVERY.md) updates selection checkmarks, keyboard-capable pickers, shortcuts and per-profile activation defaults. The results below retain the original scheduling checkpoint.

## Delivered behavior

The existing System/Max and temperature profiles use the same qualified controller and authenticated five-method helper interface. Automation chooses a profile above that controller; it cannot grant hardware qualification or weaken the immutable chip guard.

The native menu keeps one-click profile selection. A normal click activates until changed. **Activate for/until** applies to the currently acknowledged profile: Minutes (5–55 in five-minute steps), Hours (1–12 and 24), a segmented custom For/Until picker, or an exact running process instance. Until uses the next occurrence of the selected time; 24-hour display is the default, configurable in Settings. A process list includes icons and search, with an explicit switch to include helper applications and other processes. The helper/process filter is included in portable preferences. No command arguments or application contents are inspected.

**Cancel Override / Resume Schedule** ends a manual override and requests System before a fresh schedule is admitted. Manual selections, including indefinite System, always outrank schedules. At expiry or process exit, System restoration comes first, then an eligible current schedule can resume. Changing duration does not restart the active controller or disturb Apple auto at idle. Runtime timers and process watches are not persisted. Sleep, backend changes, quit and restart cancel them.

Every profile, including System and Max, has a Schedule section. Monday–Sunday support multiple ranges, enable switches and exact-minute editing. An earlier end denotes an overnight range; its continuation appears on the next day, including Sunday-to-Monday. Equal endpoints are invalid; 00:00–24:00 is all day. Boundaries are start-inclusive/end-exclusive. Date/time pauses apply to a profile or, through text import, all scheduled profiles. Manual overrides are unaffected by pauses.

Conflicts identify the existing profile and overlapping weekday/time. Each conflict supports Override or Skip; the bottom actions handle all remaining conflicts. Override subtracts only overlapping minutes, preserving the other portions of the incumbent. Skip skips the incoming range, including rolling back partial overrides made for that range. Uncontested entries survive Skip All. Review is transactional: nothing is published until the complete resulting configuration validates and saves. Cancel leaves the original configuration intact. Fragmentation that exceeds the rule limit is rejected.

The text-import sheet supplies a copyable chatbot prompt and copyable field-specific errors. It never calls an AI service. Use JSON without Markdown fences:

```json
{
  "version": 1,
  "entries": [
    {"profile": "Silent", "day": "Monday", "start": "08:30", "end": "12:30"},
    {"profile": "Silent", "day": "Monday", "start": "14:20", "end": "16:30"},
    {"profile": "Gaming", "day": "Tuesday", "start": "18:30", "end": "02:25"}
  ],
  "pauses": [
    {"profile": "Silent", "start": "2026-12-20T00:00:00Z", "end": "2027-01-04T00:00:00Z"}
  ]
}
```

Use unique exact profile names and full English weekdays. Pauses require increasing ISO-8601 dates with an explicit timezone; omit profile to pause every schedule. Weekly rules follow the Mac's local timezone. During a repeated DST hour, a range is active during both occurrences; nonexistent local minutes do not occur. No clock or power setting is modified.

## Persistence and portability

Version-two local archives atomically include profiles, schedules, pauses and preferences. Version-one archives migrate with empty schedules and default preferences. Missing optional metadata receives defaults. Invalid automation is discarded with an issue while validated profiles survive; the damaged file remains recoverable through existing preservation behavior.

Settings export/import carries the entire validated configuration. Replacement requires a native confirmation showing counts and clears runtime control intent. Individual profile files include schedules and pauses. Built-ins retain their known identities; System and Max definitions remain immutable. Custom imports receive fresh profile/rule IDs. Global pauses exported with an individual profile become scoped to that profile, avoiding a surprise global pause on the destination. Conflicting individual schedules go through the same review. Original version-one profile-only imports remain supported. Individual schedule imports preserve manual timer/process intent. A newer manual selection made while a replacement saves takes precedence over that replacement's System transition. Conflict review waits for the editing/import sheet to finish dismissing.

Portable files contain no lease, hardware authority, signing identity, process watch, previous manual selection or diagnostic recordings. Hardware eligibility is evaluated on the destination machine; raw sensor selections absent there remain visibly unavailable. Exported custom names and schedules are intentionally user data and must not be published with source.

Launch at login is enabled by default, with an explicit disable preference, using `SMAppService.mainApp`. macOS may require native Login Items approval. Diagnostics/tests do not register login items. Initial startup and wake begin with System; configured schedules may activate after fresh hardware/helper eligibility and the normal engine's acquisition gate. Saved manual selections never resume themselves.

## Menu-bar monitoring

Settings can select up to sixteen readouts and optionally show the clock. Choices include logical roles, every readable temperature key in the discovered SMC catalog, available HID temperature names, and complete model-manifest CPU/GPU/Tp/Tm region averages. Raw/group display sampling runs separately from the control loop and never supplies a control input. Missing members invalidate a group; duplicate HID names are unavailable rather than guessed. Old values become unavailable.

Physical CPU/GPU averages and per-core/performance-cluster identities remain unqualified on this M5 Pro. CPU/GPU and Tp/Tm aggregates are explicitly estimates/regions; Tp/Tm are not relabelled as performance/efficiency cores. Top remains a proximity proxy. This feature does not claim identification of every physical sensing element.

## Safety and verification

Expiry is checked before acquisition, after acquisition and before fan-command dispatch. A delayed acquisition cannot send a new command for an expired intent. Durations use monotonic elapsed time and an absolute upper bound; a forward wall-clock adjustment may end an activation early, never extend it. No caller-defined timer/deadline was added to XPC. Normal expiry is serviced by the GUI polling cadence plus I/O latency, not a hard real-time guarantee. If the GUI freezes/dies, the existing ten-second helper heartbeat timeout handles release; a dead/blocked helper cannot run that watchdog. The prior restart recovery evidence remains applicable. An already-dispatched RPC cannot be recalled, so restoration follows completion or watchdog recovery.

An active schedule that fails sensing/control is stopped for that occurrence; it does not repeatedly reacquire control. Resume Schedule explicitly allows retry, or a later occurrence can be considered. Unavailable profiles do not activate. A schedule boundary or pause requests handback before another profile is admitted. Activation checkmarks still require acknowledged control, not a schedule or timer intention.

Local results are recorded below after the final build. Visual review and active physical sleep/wake remain manual follow-ups; no screenshots, GUI automation, stress workload, power change or gaming calibration is included in this delivery.

### Recorded results

- **276 Swift tests**: 28 hardware, 175 core, 73 app. **33 Python tool tests**. New cases cover half-open/DST/overnight scheduling, subtraction, disabled/editable ranges, per-conflict transaction rollback, Skip All preservation, scoped pauses, protected/custom interchange, migration defaults, corruption/limits/authority rejection, persistence retry, manual precedence, process reuse, timer adoption, sleep reset, display isolation and expiry during an in-flight acquisition.
- Full **Address Sanitizer: 276 tests passed**, with leak detection disabled; no leak-free claim. **Thread Sanitizer: seven selected tests passed**, including delayed-acquisition expiry, preference/collection races and shared handback. The final additional check covers manual selection during an in-flight configuration save.
- Signed single-job native build and deep/strict signature verification passed. Normal ServiceManagement replacement preserved the existing identity/team. One immediate re-registration attempt returned “Operation not permitted”; registration succeeded after the replacement settled. No permission bypass or alternate installer was used. The failed early read-only check was repeated only after helper registration was enabled.
- Bounded real-controller `--automation-check` passed timer expiry and selected-process exit; both ended with helper-observed fan modes **0/0**. Subsequent **independent read-only SMC observation also found 0/0**, with both fans stopped under Apple control. No initial Max request or stress stimulus was used.
- Read-only `--sensor-menu-check` passed: **300 choices** (266 raw SMC temperatures, 17 HID names, 13 logical roles and four region aggregates). Discovery plus status/display verification took **0.243 seconds** in this session. This is one bounded observation, not a long-term performance guarantee; enumeration is separate from control.
- Production System-first functional launch passed **five ticks**, helper **controlReady**, modes **0/0**. The app is delivered in System, and native helper/login registrations both report enabled. Native aesthetics, typing into embedded menu controls, real overnight/DST time passage and physical active sleep/wake still need manual review; deterministic model/menu tests are not a claim of those physical observations.

Verification commands are `Scripts/verify.sh`, `Scripts/verify.sh --sanitizers` and `Scripts/build.sh -jobs 1`. The two fixed signed diagnostic actions above are not part of software-only CI. Raw local results, process instances, signing configuration and user configuration are excluded from the public repository.
