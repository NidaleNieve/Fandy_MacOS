# Fan response — 0.2.4 (build 19)

## Diagnosis and implementation

Existing School recordings show brief chip-envelope peaks accompanied by fan demand rises while chassis readings remain comparatively steady. Their approximately six-second spacing cannot establish individual burst durations. The old raw guard bypassed upward limiting and could accelerate the entire unrelated profile request.

Ordinary demand and guard demand are now separate. A time-weighted three-second moderate guard window is enforced independently in the helper; nominal temperatures at or above 75°C and fair pressure use raw demand immediately. Serious/critical/unknown pressure and invalid/stale readings restore Apple control. The temperature curve itself is unchanged. The 75°C boundary is an existing application-policy knee, not an Apple critical-temperature assertion. Missing history/gaps use raw current demand. Repeated observations cannot accelerate the time window.

Fan response adjusts ordinary averaging from three to zero seconds and upward slew from two to ten percentage points per second. School defaults to Quiet; other profiles to Fast. Downward hysteresis, Max, physical bounds, authentication and recovery remain in place. Settings survive profile imports/exports, duplication and undo.

CPU/GPU checkboxes select model-specific control maxima for the shared chip curve and target. Full-chip guard requirements cannot be deselected. M5 operational regional manifests partition the existing full envelope without claiming newly identified physical cores. Airflow proxy help appears only with Airflow selected; the requested estimate paragraph is removed.

## Automated verification

425 Swift tests pass (54 hardware, 223 core, 148 app), plus 52 tool tests. The native suite was rerun outside the restricted filesystem sandbox so export-panel construction could complete; all app tests, including the new editor tests, finished. Tests cover one-second bursts, sustained moderate demand, irregular/duplicate timing, conservative cold starts/gaps, immediate 75/80/85°C demand, fair/severe pressure, helper-only escalation, shared adapter guard callbacks, malformed telemetry, full-chip protection with one input deselected, missing regional members, configuration migration and editor undo/persistence. Existing authentication, command-order, watchdog, scheduling and lifecycle tests remain passing.

## Local delivery

The single-job arm64 Release build passes with version 0.2.4 / build 19 in both app and helper. The app and DMG are Developer ID signed, notarized and stapled. Matching component identities, hardened runtime, Gatekeeper assessment, mounted payload privacy and image integrity pass. The new helper replaced build 18 through verified normal-quit release, ServiceManagement unregister, job absence, installation and registration. Approval remained enabled; build 19 reported healthy startup and independently observed automatic mode on both fans.

GitHub publication is deferred until user testing. The previous public release and update feed are unchanged. No synthetic workload or new hardware transaction recipe was introduced.

## Ordinary-use observation

A bounded five-minute factory-School session on the locally tested M5 Pro completed successfully: 251 independent samples spanning 299.77 seconds, with a median 1.179-second acquisition interval (one-second pacing plus I/O). Warm chassis inputs drove a gradual rise to approximately 14–15% ordinary demand. After warmup, the largest observed adjacent demand change was 0.094 percentage point. Chip-envelope readings ranged from 41.38 to 58.95°C; the small natural burst produced a 5.93% raw guard peak and a 3.65% enforced peak. The chassis request exceeded both, so this session does not isolate a guard-driven fan surge or reproduce the earlier 69–71°C bursts. Actual fan readings ranged from 2401 to 3556 RPM during acquisition/ramp/settling.

The diagnostic verified ownership during control, then System selection, normal termination and independent automatic mode on both fans. A separate final authenticated status reported healthy build 19, enabled registration and both modes 0. The normal app was reopened; its preserved School schedule correctly resumed control despite a remembered System baseline. It was then quit normally, with another independent automatic-mode check on both fans, to finish delivery under macOS control. Saved profiles and automation were not edited. The installed build is ready to reopen; it was not left running because the current schedule would reactivate School.

Measured deterministic improvement: a one-second 30% request after zero history contributes at most 10% through the three-second Quiet window, while sustained moderate demand reaches its full value after three seconds. Immediate high-temperature behavior remains unchanged. Ordinary-use testing showed stable chassis-driven demand and attenuation of a small natural burst; larger real bursts and subjective noise still need user feedback. Sustained heat and Apple-controlled fan changes are not suppressed or guaranteed. Earlier physical recovery evidence remains applicable because transaction/release paths are unchanged; active physical sleep/wake remains unobserved.
