# Current checkpoint — 2026-10-04: compact native menu and application launch rules

0.2.0 build 3 delivers the native app icon, fully native menu actions (removing rectangular Cancel highlighting), stable centered readouts, compact inline time controls, native hosting sizing fixes, hidden profile scroll indicators, combined weekly schedule overview and per-profile application-launch/close automation. See [delivery details and semantics](UI_AUTOMATION_DELIVERY.md).

348 Swift / 46 tool tests and the signed Release build pass. GitHub run 37209040150 is green for code commit d988cb0: tests, sanitizers, native Release on macOS 15/latest. The installed `build/MonitoringDSR/Fandy.app` was replaced after verified automatic handback/unregistration; helper/login registration remain enabled. Its five-tick live startup check passes in System, fan modes 0/0, Apple ownership and no monitoring warning. The app is running in System. Existing personal profiles/signing choices remain intact. No screenshots or GUI automation were used.

Updated Test DMG/checksum/report: `build/Distribution/UI-Automation-0.2.0-build3`. This is still an Apple Development-signed, unnotarized test artifact, not a notarized distribution release. Developer ID certificate plus the private notarytool profile name remain the release blockers. No new credentials or hardware authority are stored in launch rules.

Next: human appearance review of the native menu, resizing and time controls; optional application launch/close usability check. Remote CI is complete. Broad distribution and the existing physical sleep/wake/helper restart follow-ups remain below. Do not restart hardware qualification for UI work.

---

# Previous checkpoint — 2026-10-04: Apple Silicon registry and release pipeline

0.2.0 adds compiled M1–M5 MacBook Pro reference support, preserving the tested Mac17,9 direct path. DeviceRegistry resolves identity and generation-specific source groups; selected membership/types are frozen. FanInterface admits only reviewed one/two-fan metadata and float/fpe2 encodings. ReferenceFanTransaction implements direct and bounded Ftst handover; every-fan release and global flag verification are independent of sensor health. Ingress cancellation survives queue and hardware-admission races. Monitoring retains temperatures when fan metadata fails. Imported settings and XPC requests cannot grant capability.

340 Swift / 46 tool tests pass; signed arm64 Release build passes. Final M5 profile, edit, rapid-switch, quit, disconnect, heartbeat and controller SIGKILL checks pass; detailed results, performance and limits are in [release verification](COMPATIBILITY_RELEASE_VERIFICATION.md), with [compatibility matrix](COMPATIBILITY.md).

The installed bundle remains `build/MonitoringDSR/Fandy.app`; its helper and login registration are enabled. The full bundle was replaced only after verified release/unregister; the pre-update app is backed up in ignored build storage. Diagnostics use temporary profile stores. The final delivered running app is in System; a five-tick startup check confirms modes 0/0, helper controlReady and no monitoring warning. Completion-based native unregistration/reregistration also passes. No screenshots or GUI automation were used.

Test DMG/checksum/verification.json: `build/Distribution/Compatibility-0.2.0-Delivery`. It contains an Apple Development-signed app; the Test image itself is unsigned, and neither is notarized. **The remaining release blocker is a locally installed Developer ID Application certificate and a supplied notarytool keychain profile name.** An async setup question was sent; no password/API key should be shared. `python3 Scripts/distribute.py --keychain-profile PROFILE_NAME` performs the staged app+image notarization/stapling/Gatekeeper workflow and publishes only after all checks. Build signing choices remain ignored; no credential files are introduced. See [distribution workflow](DISTRIBUTION.md).

Next steps, without restarting broad research:

1. GitHub CI is green for code commit 514d6ce: tests, sanitizers and native Release compilation on macos-15 and macos-latest. macOS 15 exposed older-SDK clock isolation and SMAppService non-Sendable async boundaries; explicit clock main-actor isolation and the documented unregister completion bridge fixed both. Remote compilation is not physical compatibility proof. No further broad software review is required before the credential-dependent distribution step.
2. Once local distribution certificate/profile are ready, verify genuine Developer ID peer status/restoration through normal Applications installation and ServiceManagement registration; run Scripts/distribute.py, verify final release ticket/Gatekeeper/mounted payload/checksum, and deliver the final DMG. The test artifact must not be relabeled notarized.
3. Root-helper SIGKILL retest remains pending because noninteractive administrator authorization was unavailable. Earlier local restart evidence is retained; source-supported legacy startup/global release is tested synthetically. Physical sleep/wake remains pending. Do not claim a blocked/dead watchdog can recover.
4. Other Macs are reference-supported, not locally tested. Comfort inputs may be absent and only dependent profiles must stay unavailable. No friend developer setup or diagnostic qualification session is required for normal supported operation.

Files: Sources/FandyHardware/DeviceRegistry.swift, ReferenceSensorKeys.swift, FanInterface.swift, ReferenceFanTransaction.swift; Sources/FandyHelper/FanHardware.swift and main.swift; core restoration/status and GUI monitoring integration; Tests/FandyHardwareTests/CompatibilityTests.swift; Scripts/distribute.py and package-dmg.py. Stats arrays are MIT-adapted with pinned revision and bundled attribution. Raw references/measurements/signing remain ignored.

---

# Current checkpoint — 2026-10-04: profile layout and native clock

Pause Schedule is a separate tab, with a separator below the tab selector. Schedule priority is a bottom tip. Chip/Chassis collapse independently; target and minimum airflow appear in graphs as a dashed request envelope using production math, without overwriting nodes. Target controls are lower, airflow has Reset, point buttons match, sidebar backgrounds are consistent, and context menus add identity-specific duplicate/export/remove. The transient unsaved line is removed. Inline For/Until uses a native segmented picker, stable positions, centered fields and AppKit's clock.

318 Swift tests, 37 tool tests and the signed Release build pass. See [profile layout delivery](PROFILE_LAYOUT_DELIVERY.md). The refreshed DMG is under `build/Distribution/2026-10-04`; existing signing/distribution/hardware limitations remain.

The installed Release app passes five live System startup ticks with Apple ownership, helper controlReady, both modes 0/0 and no monitoring warning. It is running in System after the update; helper and login registration remain enabled.

---

# Previous checkpoint — 2026-10-03: inline controls and test DMG

Time/Until and running-app conditions now open as hover submenus with embedded controls. The fan readout centers across the actual native menu width. Profiles hide scroll indicators while retaining scrolling. Git was checkpointed before edits on `codex/inline-menu-dmg`.

314 Swift tests, 37 tool tests and the signed Release build pass. A privacy-clean 1.7 MB arm64 DMG passes image and read-only mounted payload verification. It is Apple Development-signed and unnotarized; broad distribution still requires Developer ID/notarization. Physical control remains Mac17,9-only. See [inline menu and DMG delivery](INLINE_MENU_AND_DMG.md).

The installed app is updated to Release. System startup passes five live ticks with both modes 0/0, helper controlReady, Apple ownership and no monitoring warning. Helper/login registration is enabled. The update's signature check caught two stale Debug preview libraries; removing only those obsolete files restored the verified Release bundle before helper registration.

---

# Previous checkpoint — 2026-10-03: temperature goal and rename

Editable profiles now have an optional target for Chip/Trackpad/Actuator/Airflow. Target demand joins curves/floor/chip guard by maximum; qualified complete fresh inputs remain mandatory. Old profiles keep target=nil; persistence/interchange/undo support the new metadata. Header Rename+pencil and native sidebar context Rename open a focused dialog. Name-only edits preserve active control generation; protected System/Max cannot change.

314 Swift / 33 tool tests, full ASan and signed build pass. Installed startup passed five ticks in System/controlReady, modes 0/0 and no monitoring warning. See [temperature target delivery](TEMPERATURE_TARGET_DELIVERY.md) for behavior, tests and limits.

---

# Current checkpoint — 2026-10-03: compact native UI

Ordinary menu actions now use AppKit rows; the custom blue hover style, excess padding/heights, extra Choose clicks and clock readout are removed. Bounded long-name/readout handling keeps the complete menu within 256 points in layout tests. Native actions close the menu normally. Menu shortcut is Toggle Menu.

Profiles retain their native split/hosting controllers, use native table selection/doubleAction, expose Fan Curves / Schedule / When Activated tabs, and keep universal current readings in a fixed right column. Undo preserves Settings; secondary clicks edit graph nodes directly. Native sensor search and a visible raw-sensor separator are implemented. Availability rendering no longer enumerates processes repeatedly.

302 Swift tests, 33 tools, full ASan 302 and signed native build pass. Details and remaining human review are in [current UI delivery](NATIVE_UI_DELIVERY.md). Fan protocol and qualification are unchanged. Installed startup verification passed five ticks in System with no warning and modes 0/0; helper/login registrations remain enabled. The ordinary app is running System, independently observed at modes 0/0.

---

# Current checkpoint — 2026-10-03: recovery and menu/profile polish

Verified restoration clears stale GUI/controller warnings; startup explicitly verifies handback and retries transient failures. Immediate menu checkmarks indicate selection, while Starting/Restoring remains separate from acknowledged control. Timers can be attached during initialization. Menu rows wrap within fixed content width and mouse-selected profiles/presets keep tracking open. Editable/searchable pickers use keyboard-capable native popovers, including a selectable clock.

Unset global shortcuts, per-profile duration/app defaults, universal configuration Undo/Redo, contextual curve nodes, non-collapsible adjustable sidebar, corrected window-front ordering and earlier revision-two Gaming defaults are implemented. Existing edited Gaming curves survive migration. See [delivery behavior and verification](MENU_POLISH_DELIVERY.md). Software suite: 296 Swift / 33 tools; final sanitizer/build/installation results are in that report. Manual native appearance/shortcut input and physical active sleep/wake still need human review.

---

# Scheduling checkpoint — 2026-10-03

Timers (minutes/hours/custom until/process instance), weekly ranges/overnight continuation, pauses, conflict subtraction/review, chatbot text import, complete configuration interchange, scheduled profile interchange, default-on login and configurable menu temperature/clock readouts are implemented. Manual intent takes precedence and expires through System; timers/process watches never resume from disk. The five-method helper and qualified fan engine are unchanged.

276 Swift / 33 tool tests pass; ASan 276 and seven selected TSan tests pass. Signed build and real bounded timer/process-exit handback pass. Independent modes are 0/0. Read-only menu discovery exposes 300 choices, with physical-core/cluster aggregates still labelled regions/estimates rather than certified identities. See [full delivery](SCHEDULING_DELIVERY.md) for formats, limitations and results.

Resume with human testing of embedded menu text/search controls and native layout. Actual active sleep/wake needs coordinated wake; typing comfort, acoustics and sustained gaming calibration remain separate. New schedules use local wall time, while temporary intent is cancelled by sleep/restart. No pending physical fan-control gate was relaxed for these features.

---

# Development checkpoint — 2026-10-02

## Latest improvement delivery

Transactional background profile persistence, grouped native Undo/Redo, keyboard curve adjustments, fresh temperature markers, demand breakdown, local profile interchange, sanitized diagnostic export and native launch-at-login settings are implemented. The stored archive and privileged protocol remain compatible. See [delivery behavior, verification and remaining checks](IMPROVEMENT_DELIVERY.md). 235 Swift tests, 33 tool tests, full ASan and six selected TSan checks pass. Exclusive thirty-minute System/Cool Chassis sessions completed with verified handback; active full-tick p95 was 358 ms and remains an optimization opportunity. Physical active sleep/wake and subjective calibration remain pending; older checkpoints below retain their historical context.


## Working production milestone

**All six built-in profiles and eligible custom curves now work on the real Mac17,9.** The signed app starts in System with independent hardware monitoring. System immediately releases both fans to Apple. Max uses each fan's fresh reported maximum. System+, Gaming, Cool Chassis, School and custom curves use the qualified operational temperature policy. The menu checkmark now indicates selection; Starting/Restoring stays distinct from acknowledged control. Previews never masquerade as active control. System+/School may remain active while releasing ownership to Apple at idle.

The compiled stage is `qualifiedControl`, with `conservativeEnvelope` chip policy. Chip control is the maximum across a complete fixed 105-key Tp/Tm/Tg manifest, not a falsely certified CPU/GPU average. CPU/GPU estimates remain informational. Five operational chassis inputs are reviewed: Trackpad Ts0P, Actuator Ts1P, Left TaLP, Right TaRF and explicitly labelled **Top proximity TaTP**. Top is an airflow-scale proxy, not a claim that TG Pro's exact Top identity is settled. The three other proximity mappings remain informational and cannot raise demand. Missing members fail closed. This supersedes the previous inactive-envelope and maximum-only checkpoints; do not restart broad discovery or security work.

Final demand remains the maximum of applicable curves, profile floor and the independent immutable chip guard. Separate comfort scales are retained. Profiles, local signing configuration, `is.dsr.fandy` and helper identity are preserved. No manual state is restored at startup/wake.

## Native polish and focused regression

The curve editor now has a native point selector for keyboard/numerical editing, preserves exact fractional values, accepts locale decimal commas, and holds its axis range fixed during a drag. Graph endpoint segments match the engine's clamped interpolation. Closely spaced nodes stay ordered during dragging; adding a midpoint preserves the existing interpolated policy.

Editor draft state is tested independently of SwiftUI drawing. Invalid numbers/nodes stay local and show “Not applied”; only validated curves reach AppModel. Reset explicitly clears an unpublished invalid draft even when the parent retained its original value, and refreshes selected fields when node identity stays unchanged. Removing a node keeps the next useful selection. Profile reordering disables unavailable directions and protects built-in positions.

Active profiles show “Calculated demand”, while inactive previews retain “no fan commands”. CPU/GPU candidates are labelled estimates; stale, corrupt or nonfinite temperatures display Unavailable. Fan/session errors use readable messages and duplicate fault lines are omitted. Native icon controls have explicit accessibility labels. Visual review remains human-only; no screenshots or automated GUI navigation were used.

The refreshed signed live diagnostic passed every temperature profile, active editing, invalid-draft retention/correction, backend round trip, rapid switching and both-fan System handback. The hardware writer, command order, watchdog and authority were not changed in this polish pass. Earlier crash/restart evidence remains applicable; active physical sleep/wake is still a separate follow-up.

## Architecture, security and performance follow-through

The requested skills review fixed idle read failures that could trigger unowned release writes in both GUI and helper, consolidated automatic ownership states, added post-I/O lease-expiry checks, removed misleading individual-write defaults, cleaned up power-observer lifetime and rejected extra privileged command fields. The complete suite passes under Address Sanitizer; five selected concurrency cases pass Thread Sanitizer. Full SMC sampling now runs at most twice per second while expiry/restoration decisions retain their 100-ms timer. A modest steady lease reduced sampled helper CPU from roughly 15% to 5% of one core; memory remains about 12 MiB. Fresh status/target transactions remain independent.

The updated signed helper passed real controller SIGKILL, heartbeat expiry, disconnect and normal termination, with independently verified manual-to-automatic transitions on both spinning fans. Live malformed/authentication probes and measured acquisition/status/engine latency passed. See the [detailed review and explicit remaining checks](ARCHITECTURE_SECURITY_PERFORMANCE_REVIEW.md). The fixed physical sleep/wake diagnostic requires a coordinated manual wake; it is prepared, not falsely counted as a completed test.

## Hardware integration fixes

1. Automatic target preloading acknowledged writes but read back zero on this model. The reviewed production batch establishes and verifies both manual modes before validated targets. It never clears targets, uses unlock keys or tries another undocumented sequence.
2. Firmware truncates fractional RPM acknowledgements. Helper requests and independent guard escalation now round upward to integral RPM within each fan's verified bounds; target-ownership tracking uses the normalized values.
3. Warm fan restart can take about nine seconds to report positive RPM. The finite fifteen-second qualification observation accommodates that; the production ten-second stalled-fan check remains active.
4. The client reuses only immediately issued observations, at most 250 ms old, avoiding redundant status traffic. The helper independently samples before every transaction and retains its existing admission limits.
5. Editing an active curve with unchanged required inputs retains its valid production lease. Qualification deadlines cannot be extended. Separate UI/helper generations preserve stale-reply protection and allow simulation-to-hardware round trips without reusing stale lease generations.

## Physical acceptance

| Case | Actual result |
| --- | --- |
| Original automatic restoration | Both manual 1 → automatic 0; three idempotent requests and 60 seconds independently observed. |
| First modest mechanical trial | Both accepted spinning minimum + 200 RPM, actual rotation and five-second automatic handback. |
| Variable-speed upward trial / warm re-entry / target changes | Passed mode, target and actual-RPM observations, followed by both-fan automatic release. |
| Variable heartbeat expiry | Both automatic at approximately 10.51 seconds. |
| Variable owned disconnect | Both automatic at approximately 1.04 seconds. |
| Nonrenewable qualification deadline | Both automatic at approximately 15.14 seconds despite renewal. |
| Variable controller SIGKILL | Independent observation saw both automatic approximately 0.17 seconds after the kill, following actual rotation. |
| Normal variable-speed termination | Both mode 1 → 0 with rotation observed before cleanup. |
| Helper SIGKILL/restart | Previously passed launchd restart/startup release during modest ownership, approximately 0.31 seconds. Startup restoration is unchanged. |
| System+, School | Acknowledged automatic-at-idle, both mode 0. |
| Gaming | Acknowledged manual control and actual RPM near each reported spinning minimum. |
| Cool Chassis | Acknowledged 20% demand, approximately 3420 RPM independently observed. |
| Custom curve | Acknowledged 5% request, approximately 2595 RPM; live edit to 10% remained manual and reached approximately 2868 RPM. |
| Simulation → hardware / rapid switching / System | Passed renewed real activation, final acknowledged System and both independent automatic modes. |
| Max | Final regression reached approximately 7819 / 7817 RPM against then-reported 7826 maxima, followed by both automatic modes. Limits remain hardware-derived. |

A dead or blocked helper cannot run its watchdog. Measured launchd restart recovery does not guarantee recovery from blocked kernel I/O. Actual active sleep/wake remains unobserved; both process state machines and native power notifications are implemented and model-tested. No temporary helper-kill operation remains in production.

## Five-minute ordinary-use comparisons

A fixed native-model diagnostic recorded five minutes each of System, System+ and Cool Chassis, ending in System. These were sequential measurements under ordinary quiet use, not a controlled thermal/acoustic study. The machine was already cooler than the supplied comfort baseline.

| Median reading | System | System+ | Cool Chassis |
| --- | ---: | ---: | ---: |
| Chip envelope °C | 32.03 | 31.16 | 28.41 |
| Trackpad °C | 24.19 | 23.88 | 23.56 |
| Actuator °C | 22.69 | 22.44 | 22.03 |
| Left °C | 29.75 | 28.89 | 26.57 |
| Top proximity °C | 30.22 | 29.46 | 26.49 |
| Right °C | 29.73 | 28.96 | 26.57 |
| Fan RPM, left / right | 0 / 0 | 0 / 0 | 3420 / 3419 |
| Ownership | Apple automatic | Apple automatic | Fandy manual |

System and System+ correctly requested zero custom demand in this idle session. Cool Chassis ramped to its initial 20% floor, then held both targets at 3419 RPM for the final 200 recorded samples without target hunting. Natural cooling and sequential order prevent attributing all temperature changes to a profile. Initial defaults are retained; no claimed typing-comfort or sustained-gaming calibration follows from this cold idle session.

## Verification and installed delivery

**221 Swift tests pass: 28 hardware, 150 core, 43 app. All 31 Python tool tests pass.** Single-job signed native compilation and strict deep signature verification pass. Coverage includes interpolation, validation, aggregation, persistence, chip-envelope completeness, policy-specific eligibility, helper authentication/admission, whole-RPM normalization, partial failures, lifecycle races, lease continuation, bounded deadlines, exact editor values, reset/invalid-draft behavior, node interpolation and stale display values.

The final signed live check passed every temperature profile, active custom editing without mode release, simulation-to-hardware reactivation, rapid switching and normal cleanup. One earlier zero-delay diagnostic status flood hit the existing request limit; polling now follows production pacing. A separate transient metadata rejection restored both fans, was not reproduced in the final complete run, and retains focused fan-only diagnostics without weaker validation.

The registered signed bundle is preserved as `build/MonitoringDSR/Fandy.app`, installed through verified release/unregister, old-service absence, signature verification, replacement and normal SMAppService registration. The final functional launch passed five real-monitoring ticks in System with a control-ready helper and Apple-observed ownership. Independent readings confirmed both mode 0, target 0 and stopped fans; the normal menu-bar app was then launched in System. Raw measurements, reference exports, local signing configuration and detailed local handoff stay ignored by Git. No screenshots, GUI automation or Computer Use were used.

## Remaining work

1. Observe actual sleep/wake from active custom ownership and verify both automatic modes after wake. This requires an intentional interruption of the machine; do not report the model test as hardware proof.
2. Gather subjective comfort/noise feedback under a warmer typing workload, then tune Cool Chassis/School toward the supplied 27°C Trackpad, 25°C Actuator and 33°C Airflow baseline without forcing exact temperatures.
3. Calibrate sustained gaming under a real game separately; no synthetic stress, power/clock changes or promised 75–85°C result.
4. Human review of the native editor and menu. Release signing/notarization/distribution are separate from this installed development build.
5. Exact CPU/GPU averages/physical identities, exact TG Pro Top semantics and the three proximity labels remain optional research goals. They are disclosed estimates/proxies, not production control substitutions. Additional Apple Silicon models require their own reviewed manifest/topology/recovery evidence.

## Resume / reproduce

Read this checkpoint, [temperature-profile evidence](TEMPERATURE_PROFILE_STATUS.md), [hardware gates](HARDWARE_GATES.md), [chip policy](CHIP_ENVELOPE.md) and [sensor evidence](SENSOR_EVIDENCE.md). Detailed artifact names and local service state are in ignored `docs/local/DEVELOPMENT_HANDOFF.md`.

```sh
Scripts/test.sh -j 1 --no-parallel
python3 -m unittest discover -s Tests/ToolTests -v
Scripts/build.sh -jobs 1
```

Fixed signed `--profiles-live-check` tests native model activation, active editing and its draft validation boundary, simulation round trip, rapid switching and cleanup without changing stored user profiles. `--profiles-calibration-check` logs five minutes per comparison profile and ends in System. They perform real writes and should not run alongside an active controller. No caller chooses RPM, keys or qualification authority. Never overwrite a registered bundle: release/unregister, confirm service absent, replace, verify signatures and register.
