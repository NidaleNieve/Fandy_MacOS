# Fandy

A small native Apple Silicon macOS menu-bar fan controller with named profiles and editable temperature curves.

**Current build: real monitoring, editable profiles, live previews, and a verified automatic-restoration helper. Custom fan control remains gated by sensor qualification.** On Mac17,9 / M5 Pro, Fandy restored both fans from mode 1 to mode 0, passed three repeated requests, and independently observed automatic ownership for 60 seconds. No manual mode, RPM target, or target-clearing command has been issued. The physical manual-mode/target methods still reject requests. This is restoration-qualified, not a completed custom controller.

The next manual-test admission/deadline model is implemented and tested without a physical writer or new XPC operation. See [remaining sensor coverage](docs/SENSOR_EVIDENCE.md) and [bounded test preparation](docs/MANUAL_QUALIFICATION.md) for the exact blockers and next gate.

See [the development checkpoint and remaining work](docs/DEVELOPMENT_STATUS.md) for the current milestone and resumption order.

## Build and run

Requires Apple Silicon, macOS 15+, Xcode 16+ with Swift 6. Tested here with Xcode 27 / Swift 6.4 on Mac17,9 (M5 Pro).

```sh
Scripts/test.sh -j 1 --no-parallel
Scripts/build.sh -jobs 1
open build/DerivedData/Build/Products/Debug/Fandy.app
```

Open `Fandy.xcodeproj` and use the shared **Fandy** scheme. It has two native targets: the user app and its bundled helper. Core and read-only hardware libraries are local Swift package products. There are no external dependencies. `Scripts/generate-project.py` regenerates the small project deterministically. Signing choices made in Xcode are migrated by regeneration into ignored per-configuration `.local.xcconfig` files. New developers can set their team in the ignored `Config/Signing.local.xcconfig`; see [local configuration](docs/LOCAL_CONFIGURATION.md). Bundle naming follows the owner’s `is.dsr.<project>` convention: app `is.dsr.fandy`, helper `is.dsr.fandy.fan-helper`. For another developer, select their team and development identity in Xcode. An unsigned model/UI build is available with `Scripts/build.sh CODE_SIGNING_ALLOWED=NO`; it cannot authenticate to a production helper.

The app starts in the menu bar with its editor closed, in **System**, with **real hardware monitoring** enabled. Simulation is an explicit development option in Settings or the `--simulation` launch argument. Click the fan menu icon to select a profile in one click. **Edit Profiles…** opens the compact native editor. Drag a node, select it to edit exact °C/% values, or add/remove nodes. Invalid drafts stay visible but never replace the validated profile. Trackpad, Actuator and Airflow have separate comfort curves because their temperatures use different scales. Built-ins remain available; System and Max are immutable; other built-ins can be reset. Custom profiles support creation, duplication, renaming, deletion and reordering.

Settings includes deterministic comfortable, warm chassis, gaming, GPU hot, sensor failure, stale sensor, disconnected helper and overheating scenarios. Monitoring is the default; readings remain labelled **candidate** until corroborated. Selecting a profile in the editor calculates a shadow demand, labeled as a preview with no fan commands. Unqualified profiles cannot activate from the menu or editor. Preview values never enter a control lease, and stale/missing inputs make the preview unavailable. A System checkmark is withheld if another application is visibly using manual fan mode. Selecting System requests verified automatic restoration. Firmware mode 3 is unqualified on this model and does not receive an Apple-ownership checkmark.

## Profiles

| Profile | Meaning |
| --- | --- |
| System | Release ownership to Apple automatic mode when the real backend is qualified; no custom requests. |
| Max | Each physical fan's reported maximum, never a shared hard-coded RPM. |
| System+ | Mild editable curve; Apple automatic mode at zero demand. |
| Cool Chassis | Trackpad/Actuator/Airflow curves with an initial 20% spinning fan floor. |
| Gaming | Progressively stronger chip cooling around 77–85°C. |
| School | Gentler comfort demand with automatic mode at idle. |

These are initial policies, not acoustically or thermally calibrated defaults. The immutable chip guard remains active for every custom profile. Neither System+ nor the comfort profiles multiply Apple's hidden demand. Manual 0% means a fan's reported spinning minimum; stopped fans are possible in Apple automatic mode.

## Read-only discovery

```sh
build/swift/debug/fandy-discover --prefix T --samples 60 --interval 1 > build/sensors.jsonl
python3 Scripts/correlate-sensors.py build/sensors.jsonl '/path/to/TG Pro Log.csv'
```

The discovery executable has no SMC write API. It logs temperature keys, metadata, fan modes/ranges/RPM, and optional vendor-temperature HID events. It never requests keyboard, mouse or trackpad input events. No Accessibility, Screen Recording or other privacy permissions are used. See [sensor candidates and qualification requirements](docs/SENSOR_EVIDENCE.md). Raw recordings, temperature-reference exports and local evidence reports are intentionally excluded from Git. Offline comparison never qualifies sensors automatically; normal monitoring reads hardware independently of TG Pro.

## Restoration helper and diagnostics

The current helper permits automatic mode 0 only on the observed Mac17,9 fan topology and exact lowercase mode-key metadata. Manual leases and target writes remain rejected. It restores at startup, sleep/wake, and explicit System requests, independently of temperature qualification.

```sh
build/MonitoringDSR/Fandy.app/Contents/MacOS/Fandy --helper-restoration-status
build/MonitoringDSR/Fandy.app/Contents/MacOS/Fandy --helper-restore
```

The fixed restoration flags also include `--helper-restoration-register`, `--helper-restoration-unregister`, and `--helper-restoration-check`. They accept no hardware or payload arguments. Check performs three automatic-only requests and a 60-second independent observation; it distinguishes real manual handback from idempotence. Unregister restores first. Background registration uses SMAppService and native macOS approval; no custom root installer is used.

The signed development app also accepts `--helper-restoration-protocol-check`. Against a confirmed restoration-only helper it sends fixed malformed/unqualified requests, checks reconnection and rejects a deliberately incorrect helper identity. It cannot accept caller-selected payloads or run against a manually qualified service. This is protocol verification, not live manual watchdog qualification. Settings exposes sensor-role, handback and manual/recovery verification separately.

The registered bundle is preserved separately from Xcode build output. Do not remove or overwrite it while registered. The original observation service was unregistered before replacement; its old diagnostic flags are retained only for observation builds.

The separate development-only `build/swift/debug/fandy-measure --bounded-cycle` performs a fixed 16-minute sensor recording under verified automatic ownership, including two low-duty 30-second CPU/GPU pulses. It aborts on ownership loss, stale/missing chip inputs, serious thermal pressure, or the 75°C diagnostic ceiling. It cannot write fans and is not normal app functionality. Measurement and qualification results are recorded in [hardware gates](docs/HARDWARE_GATES.md).

Sensor comparison also supports `--json`, explicitly flags flat/ambiguous data, and never edits qualification. Run its tests using `python3 -m unittest discover -s Tests/ToolTests -v`.

Profiles and rotating diagnostic logs are local in `~/Library/Application Support/Fandy/`. Logs contain temperatures, fan data, thermal pressure and profile name; no application contents or personal telemetry. Normal operation has no networking. A previous profile name is saved for reference only; it never restores manual state at launch or wake.

Verification: [hardware gates](docs/HARDWARE_GATES.md). Detailed local test/build recordings remain private; the public repository includes reproducible tests and their commands.

Read [ARCHITECTURE.md](ARCHITECTURE.md), [SAFETY.md](SAFETY.md), [SECURITY.md](SECURITY.md) and [hardware gates](docs/HARDWARE_GATES.md) before enabling any hardware-control code. Human visual review remains pending; no screenshot or automated GUI testing was used.
