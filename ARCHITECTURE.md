# Architecture

## Process boundaries

`FandyApp` is an ordinary user process: SwiftUI MenuBarExtra, profile editor, model/persistence, controller loop and diagnostics. Views never access SMC. `FandyCore` contains Foundation-only curve, profile, sensor, fan, governor, state-machine and helper safety models. `FandyHardware` exposes read-only SMC, an automatic-only command codec with an injected transport, and optional HID temperature adapters behind `TemperatureSensorProvider`. `CSMC` independently describes the reverse-engineered 80-byte userspace AppleSMC ABI; it exports reads and enumeration only.

`FandyFanHelper` is a separate, minimal root launch daemon bundled under `Contents/Library/HelperTools`. It privately owns the candidate restoration writer. Physical manual-mode/target methods reject. Automatic restoration has passed; all-sensor qualification remains required before implementing the bounded manual test path. It exposes four fixed XPC methods, authenticates the app through a public code-signing requirement, serializes I/O with a watchdog and IOPM notifications, and maintains no on-disk lease or target. The GUI never runs as root.

The Xcode app target embeds the helper and its `Contents/Library/LaunchDaemons/is.dsr.fandy.fan-helper.plist`. The app uses `SMAppService.daemon` for registration after qualification. User approval of background service registration follows macOS's native flow. Restoration-only registration is enabled; custom-control authority remains disabled; no legacy SMJobBless, custom kernel code or generic root operations are used.

## Hardware facts and limits

AppleSMC userspace transactions, temperature identities, mode semantics and fan target semantics are reverse engineered. They are not a stable supported Apple API. On this Mac17,9 we read FNum=2, flt4 RPM keys and lowercase `F0md` / `F1md` ui8 mode keys. Both fans reported minimum 2317 and maximum 7826 in the sampled session; the implementation reads them every time. Model-scoped physical IDs0/1 were independently observed and allow automatic-release attempts even when RPM/count telemetry is corrupt. Unexpected topology prevents custom activation. No Ftst key was enumerated. These are observations, not universal Apple Silicon constants.

Read-only discovery enumerates #KEY/key-at-index, retains type and raw bytes, decodes explicitly supported representations, and rejects non-finite temperatures. Unknown types remain unknown. ioft interpretation is exploratory and is not used for the active sensor registry. Friendly mappings are scoped to a machine model and individually carry qualification status. Missing keys never become zero. Other models can gain separate verified registries without changing views or the engine; they currently fail closed.

CPU and GPU groups have average display readings and peak control readings. Candidate membership follows the open-source Stats M5 list, not broad prefix matching. TG Pro reports four GPU regions here; the relationship to the candidate SMC GPU sensors has not been proved. HID supplies PMU-labelled readings, not a verified substitute for CPU/GPU peaks or the comfort sensors.

## Policy and curves

A version-1 profile contains ID/name/kind, built-in identity/default revision, four possible enabled curves, a normalized floor and an automatic-at-idle setting. Each curve contains 2–32 UUID nodes with finite ordered temperatures (0–125°C) and nondecreasing percentages (0–100). Linear interpolation saturates at either endpoint. Invalid drafts are never activated.

The chip curve uses max(CPU peak, GPU peak). Airflow uses max(Left, Top, Right). Trackpad and Actuator each evaluate their own temperature scale. Proximity sensors are display/logging only in v1, preventing charging heat alone from controlling comfort. Final demand is max(all enabled curve requests, profile floor, immutable chip guard). No comfort demand can suppress chip cooling.

Cool Chassis uses the user's comfortable baseline (Trackpad 27°C, Actuator 25°C, Airflow 33°C) and warmer observation (31°C, 29°C, 43–44°C) as two empirical calibration points. Initial trackpad nodes are 27/20%, 29/25%, 31/40%, 34/60%, 38/85%, 42/100%; Actuator temperatures are 2°C lower. Airflow has 33/20%, 36/25%, 40/40%, 44/55%, 50/75%, 60/100%. These are editable starting points, not final measured acoustic defaults. School's comfort demands are max(0, Cool Chassis percentage / 2 - 10).

Gaming starts at 55/0%, 65/25%, 72/45%, 77/65%, 81/85%, 85/100%. The immutable guard starts at 55/0%, 65/15%, 75/40%, 80/70%, 85/100%. 85°C is an application cooling policy derived from the requested gaming operating region, not an Apple emergency threshold. ProcessInfo serious/critical/unknown thermal pressure relinquishes control.

A demand governor permits fast rises, holds decreases for five seconds, uses a 2% deadband and exponential downward smoothing with a five-second time constant, and limits ordinary rise/fall to 10/2 percentage points per second. Safety increases and Max bypass upward limiting. System+/School remain automatic when initially idle; sustained zero demand releases manual ownership after 15 seconds. Ordinary reacquisition requires at least 5% demand for three seconds; a chip guard request bypasses that delay. Each fan maps independently: minRPM + percentage / 100 × (maxRPM − minRPM).

## State and communication

Controller states are system, initializingCustom, customActive, restoringSystem and fault. Five distinct healthy acquisitions are required before initial custom activation. A generation rejects late acknowledgements after rapid profile switching. Restoration is reported complete only after confirmation. Sleep/wake, sensor invalidity and helper errors reset selection to System; restoration failure remains fault and is retried.

XPC uses bounded versioned JSON inside Data (16 KiB maximum), fixed value types and connection-owned UUID leases. The helper independently samples and validates required sensors, fan IDs, bounds, message generation, snapshot freshness and thermal pressure. It applies its immutable guard even if the GUI sends lower targets. Successful validated target transactions serve as the heartbeat; status requests cannot renew a lease. Every command is serialized with a 500 ms watchdog; lease lifetime is ten seconds. A stale lease ID never survives restart. Same-connection generation ordering is enforced; a newly authenticated connection can establish a new generation after release.

Application diagnostics rotate at 1 MiB with three archives. The root helper uses unified logging only; no client-supplied file path exists. Startup, wake and faults do not restore saved profiles. See SAFETY for the difference between software tests and physical qualification.

## Production monitoring and qualification

Normal startup uses real read-only monitoring and selects System; simulation is an explicit option. AppModel injects the sensor provider, privileged client, clock and helper availability for deterministic testing. It separately exposes observed fan ownership, helper health, local signed capabilities and profile eligibility. A custom profile checkmark requires genuine acknowledged control; Apple ownership is determined from fresh fan readings, not the selected profile name.

HardwareCapabilities replaces global qualification booleans. Its immutable model, stage, per-role evidence, topology status and restoration/manual proof determine authority. The stages are observation, restorationQualification, manualQualification and qualifiedControl. Restoration authority requires the exact supported model and observed topology, independently of temperature health or qualification. Every requested chip/chassis/proximity identity, automatic/manual proof and qualifiedControl are required for leased custom control. Unsupported models receive observation-only, empty capabilities. These values originate in signed code, not preferences, environment variables, files or XPC command payloads. Helper reports cannot grant local client authority.

ShadowProfileEngine creates a private informational copy of candidate readings, evaluates the existing engine and returns ProfilePreview. This type carries percentages and provenance, but no fan targets or control effects. Strict control evaluation continues to reject unverified readings. Missing, stale, corrupt and nonfinite inputs block previews too. Profile edits update preview demand without taking ownership.

The compiled stage is restorationQualification. The helper can release automatic mode but cannot begin a lease or apply targets. Wire-version-2 status includes optional capability, restoration and retained startup-restoration reports. The registered bundle is preserved independently of build output.

`ManualQualificationPlan` and `ManualQualificationSession` are disconnected pure models for the next physical gate. They use separate `canQualifyManual` authority, fixed helper-derived +200 RPM targets, a five-second initial deadline, a fifteen-second recovery deadline and a ten-second heartbeat limit. They check all required roles, fresh acquisition, ownership and unchanged fan topology. No XPC endpoint or physical writer invokes them yet; revocation is a restoration decision, not a physical-success report.

Restoration reports contain each fan's readback and error, retain partial successes and fail overall if any attempt or confirmation fails. Restoration does not clear fan targets. The command codec permits only canonical lowercase F<n>md metadata and automatic mode 0; firmware mode 3 is rejected and left untouched. A separate helper-only transport checks root UID and compiled model authority before calling IOKit. Physical manual-mode/target methods still reject. Lifecycle tokens protect the app against stale reads and replies; XPC operation tokens prevent late lease replies from restarting an obsolete transaction. Quit becomes termination-ready only after the cleanup attempt finishes.

The development-only FandyMeasurement executable reads SMC independently and has no XPC or fan writer. A fixed phase schedule permits at most two 30-second low-duty stimuli, guarded by fresh automatic fan modes, complete candidate chip values and a75°C diagnostic ceiling. Core admission/schedule logic is tested; the tool is excluded from the bundled app/helper.
