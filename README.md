# Fandy

A small native Apple Silicon macOS menu-bar fan controller with named profiles and editable temperature curves.

**Current build: real control with all built-in profiles and custom curves on the qualified Mac17,9.** System+, Cool Chassis, Gaming and School use independently read hardware temperatures. System releases control to macOS; Max uses each fan's actual reported maximum. The signed helper, watchdog, crash recovery and native editor are integrated. See [delivery status](docs/DEVELOPMENT_STATUS.md).

Menu/profile polish includes optional global shortcuts, per-profile activation defaults, universal undo, contextual curve editing, a persistent adjustable sidebar, an observed fan-speed bar and native time/app popovers. [Behavior and verification](docs/MENU_POLISH_DELIVERY.md).

Chip control uses a separately named conservative **Chip envelope** across a fixed 105-key model manifest. CPU/GPU averages remain labelled estimates. Chassis control uses Trackpad, Actuator, Left/Right airflow and an explicitly labelled **Top proximity** input. These are reviewed operational inputs, not a claim that every physical sensor identity is certified. [Sensor evidence and limitations](docs/SENSOR_EVIDENCE.md).

## Build and run

Requires Apple Silicon, macOS 15+, Xcode 16+ with Swift 6. Tested here with Xcode 27 / Swift 6.4 on Mac17,9 (M5 Pro).

```sh
Scripts/test.sh -j 1 --no-parallel
Scripts/build.sh -jobs 1
open build/DerivedData/Build/Products/Debug/Fandy.app
```

Open `Fandy.xcodeproj` and use the shared **Fandy** scheme. It has two native targets: the user app and its bundled helper. Core and read-only hardware libraries are local Swift package products. There are no external dependencies. `Scripts/generate-project.py` regenerates the small project deterministically. Signing choices made in Xcode are migrated by regeneration into ignored per-configuration `.local.xcconfig` files. New developers can set their team in the ignored `Config/Signing.local.xcconfig`; see [local configuration](docs/LOCAL_CONFIGURATION.md). Bundle naming follows the owner’s `is.dsr.<project>` convention: app `is.dsr.fandy`, helper `is.dsr.fandy.fan-helper`. For another developer, select their team and development identity in Xcode. An unsigned model/UI build is available with `Scripts/build.sh CODE_SIGNING_ALLOWED=NO`; it cannot authenticate to a production helper.

The app starts in the menu bar with its editor closed, in **System**, with **real hardware monitoring** enabled. Simulation is an explicit development option in Settings or the `--simulation` launch argument. Click the fan menu icon to select a profile in one click. **Edit Profiles…** opens the compact native editor. Drag a node or choose it with the native point selector; press Return to apply exact °C/% values. Decimal-comma input is supported for those locales. Add/remove nodes or reset the curve as needed. Invalid changes are marked “Not applied” and keep the last valid profile running. Invalid drafts stay visible but never replace the validated profile. Trackpad, Actuator and Airflow have separate comfort curves because their temperatures use different scales. Built-ins remain available; System and Max are immutable; other built-ins can be reset. Custom profiles support creation, duplication, renaming, deletion and reordering.

Settings includes deterministic comfortable, warm chassis, gaming, GPU hot, sensor failure, stale sensor, disconnected helper and overheating scenarios. Real monitoring is the default. Reviewed control inputs are distinguished from informational CPU/GPU estimates and unresolved proximity candidates. Selecting a profile in the editor calculates a shadow demand, labeled as a preview with no fan commands. Unqualified profiles cannot activate from the menu or editor. Preview values never enter a control lease, and stale/missing inputs make the preview unavailable. A System checkmark is withheld if another application is visibly using manual fan mode. Selecting System requests verified automatic restoration. Firmware mode 3 is unqualified on this model and does not receive an Apple-ownership checkmark.

## Profiles

| Profile | Meaning |
| --- | --- |
| System | Release ownership to Apple automatic mode when the real backend is qualified; no custom requests. |
| Max | Each physical fan's reported maximum, never a shared hard-coded RPM. |
| System+ | Mild editable curve; Apple automatic mode at zero demand. |
| Cool Chassis | Trackpad/Actuator/Airflow curves with an initial 20% spinning fan floor. |
| Gaming | Progressively stronger chip cooling around 77–85°C. |
| School | Gentler comfort demand with automatic mode at idle. |

All six built-ins and eligible custom curves are operational on the qualified model. These are initial policies, not acoustically or thermally calibrated defaults. The immutable chip guard remains active for every custom profile. Neither System+ nor the comfort profiles multiply Apple's hidden demand. Manual 0% means a fan's reported spinning minimum; stopped fans are possible in Apple automatic mode.

## Read-only discovery

```sh
build/swift/debug/fandy-discover --prefix T --samples 60 --interval 1 > build/sensors.jsonl
python3 Scripts/correlate-sensors.py build/sensors.jsonl '/path/to/TG Pro Log.csv'
```

The discovery executable has no SMC write API. It logs temperature keys, metadata, fan modes/ranges/RPM, and optional vendor-temperature HID events. It never requests keyboard, mouse or trackpad input events. No Accessibility, Screen Recording or other privacy permissions are used. See [sensor candidates and qualification requirements](docs/SENSOR_EVIDENCE.md). Raw recordings, temperature-reference exports and local evidence reports are intentionally excluded from Git. Offline comparison never qualifies sensors automatically; normal monitoring reads hardware independently of TG Pro.

## Restoration helper and diagnostics

The current helper permits automatic mode 0, fixed maximum leases and qualified temperature-profile leases on Mac17,9. An empty sensor requirement means fixed maximum only: the helper rejects lower targets. Temperature profiles require the compiled policy's complete, fresh operational inputs. Restoration remains independent of temperatures. Startup and wake are System-first.

```sh
build/MonitoringDSR/Fandy.app/Contents/MacOS/Fandy --helper-restoration-status
build/MonitoringDSR/Fandy.app/Contents/MacOS/Fandy --helper-restore
```

The fixed `--helper-restoration-register` and `--helper-restoration-unregister` flags accept no hardware or payload arguments. Unregister restores first. Background registration uses SMAppService and native macOS approval; no custom root installer is used. The older `--helper-restoration-check` diagnostic is restricted to qualification builds: it performs three automatic-only requests and a 60-second independent observation, distinguishing real manual handback from idempotence. Use the production Max diagnostics below for the current control-capable build.

The signed development app also accepts `--helper-restoration-protocol-check`. Against a confirmed non-production helper with no active trial it sends fixed malformed/unqualified requests, checks reconnection and rejects a deliberately incorrect helper identity. It cannot accept caller-selected payloads or run against a manually qualified service. This is protocol verification, not live manual watchdog qualification. Settings exposes sensor-role, handback and manual/recovery verification separately. Six operational control inputs are reviewed; exact CPU/GPU averaging and three proximity identities remain informational research goals.

Older recovery-stage builds used the signed app's fixed `--helper-recovery-initial`, `--helper-recovery-deadline`, `--helper-recovery-heartbeat`, `--helper-recovery-disconnect` and `--helper-recovery-hold` diagnostics. They accept no hardware/duration parameters and must wait for exclusive ownership. Initial deadline is5 seconds; subsequent mechanical trials are15 seconds with a10-second heartbeat timeout. [Exact admission and actual results](docs/MANUAL_QUALIFICATION.md).

The production app has fixed `--profile-max-check`, `--profile-max-quit-check` and `--profile-max-heartbeat-check` diagnostics. These temporarily run Max, verify actual RPM, and verify System/termination/heartbeat handback. They accept no RPM, fan or duration arguments. They are development tests, not needed for normal use. The temporary own-helper SIGKILL diagnostic was removed after the restart test. The bounded curve-qualification stage is disabled in production after successful variable-speed recovery acceptance. Fixed `--profiles-live-check` and `--profiles-calibration-check` diagnostics exercise native model activation and ordinary-use logging without touching the user's stored profiles. The calibration records five minutes each of System, System+ and Cool Chassis and ends in System.

The registered bundle is preserved separately from Xcode build output. Do not remove or overwrite it while registered. The original observation service was unregistered before replacement; its old diagnostic flags are retained only for observation builds.

The separate development-only `build/swift/debug/fandy-measure --bounded-cycle` performs a fixed 11-minute sensor recording under verified automatic ownership, including two low-duty 30-second CPU/GPU pulses. It aborts on ownership loss, stale/missing chip inputs, serious thermal pressure, or the 75°C diagnostic ceiling. It cannot write fans and is not normal app functionality. Measurement and qualification results are recorded in [hardware gates](docs/HARDWARE_GATES.md).

Sensor comparison also supports `--json`, explicitly flags flat/ambiguous data, and never edits qualification. Run its tests using `python3 -m unittest discover -s Tests/ToolTests -v`.

Profiles and rotating diagnostic logs are local in `~/Library/Application Support/Fandy/`. Logs contain temperatures, fan data, thermal pressure and profile name; no application contents or personal telemetry. Normal operation has no networking. A previous profile name is saved for reference only; it never restores manual state at launch or wake.

Verification: [hardware gates](docs/HARDWARE_GATES.md). Detailed local test/build recordings remain private; the public repository includes reproducible tests and their commands.

Read [ARCHITECTURE.md](ARCHITECTURE.md), [SAFETY.md](SAFETY.md), [SECURITY.md](SECURITY.md) and [hardware gates](docs/HARDWARE_GATES.md) before enabling any hardware-control code. Human visual review remains pending; no screenshot or automated GUI testing was used.

## Profile files and editor shortcuts

The sidebar menu imports/exports individual profiles with schedules. Built-ins retain their identities and protected definitions; custom imports receive fresh identifiers. Imports validate and save before publication, with conflict review for schedules. Arrow keys edit the selected graph node; Shift uses finer increments. Undo/Redo reverses valid profile edits and groups a drag into one operation. Storage failures retain an explicit unsaved/error state with Retry.

Settings provide launch at login (enabled by default, with an explicit disable option), portable configuration files, configurable temperature/clock readouts and a local sanitized diagnostic export. Login starts in System; eligible configured schedules can run after fresh checks. Enabling login does not install or approve the privileged helper. No networking or automatic uploads are introduced. See [improvement delivery](docs/IMPROVEMENT_DELIVERY.md) for verification and remaining calibration.

## Timers and weekly schedules

Select a profile normally to use it until changed. **Activate for/until** adds a duration, next clock time or running-application condition to the active profile. **Resume Schedule** ends that override and returns to weekly automation through System.

Each profile's Schedule section supports multiple daily ranges, overnight continuation, pauses and conflict review. Import Schedule from Text includes a copyable chatbot format prompt and errors. Settings export/import replaces profiles, schedules and preferences; individual exports include their schedules. Runtime timers and hardware qualification are never transferred. See [scheduling delivery and format](docs/SCHEDULING_DELIVERY.md).
