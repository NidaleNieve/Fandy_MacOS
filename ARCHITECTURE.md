# Architecture

Fandy is a native menu-bar app with a separate privileged fan helper. Profiles, schedules and preferences stay on the Mac. Sparkle handles signed updates from GitHub.

## Project layout

| Target | Responsibility |
| --- | --- |
| `FandyApp` | AppKit menu and windows, SwiftUI editors, automation, persistence coordination and updater. Runs as the logged-in user. |
| `FandyCore` | Profiles, curves, schedules, persistence formats, controller state and helper safety rules. Hardware access is injected. |
| `FandyHardware` | Model registry, sensor acquisition, fan metadata and validated transaction adapters. |
| `CSMC` | C bridge for AppleSMC reads/enumeration and HID temperature events. |
| `FandyHelper` | Authenticated XPC service, serialized hardware writes, automatic restoration and watchdog. Runs as root. |
| `FandyDiscovery` / `FandyMeasurement` | Developer discovery and bounded measurement tools. Excluded from the app bundle. |

`Package.swift` defines the libraries, executables and tests. `Fandy.xcodeproj` builds the app bundle, embeds Sparkle and the helper, generates its icon, and includes license notices. `Scripts/generate-project.py` regenerates the project while preserving ignored local signing settings.

## Installation and trust

The supported installation is `/Applications/Fandy.app`. ServiceManagement registers the embedded `is.dsr.fandy.fan-control-v2` daemon from that fixed location. The app checks its resource signature, app/helper identifiers, signing teams and signing classes before registration. Background App Activity approval is separate from hardware readiness.

Both processes authenticate their XPC peer against an Apple signing chain, matching team and exact bundle identifier. The interface carries bounded versioned JSON for status, leases and targets, plus automatic restoration and a qualification endpoint that production capabilities disable. It provides no general shell, file or arbitrary-SMC-key operation.

The two predecessor daemon plists remain bundled so upgrades can unregister older services safely. Migration first restores a reachable helper; a stale unauthenticated predecessor requires independent proof of automatic ownership before removal. Registration status alone never proves that fan control is ready.

## Control flow

The app resolves manual selections, temporary overrides, application triggers and weekly schedules into a profile. `ControlMachine` validates fresh snapshots and profile eligibility, then `FanXPCClient` requests a connection-owned lease. The helper independently checks capabilities, required sensors, thermal pressure, fan bounds and ownership before admitting targets.

Temperature profiles require five healthy acquisitions before initial activation; Max requires a fresh valid fan snapshot and always requests each fan's reported maximum. A changed generation invalidates obsolete replies. Status calls do not renew a lease; accepted target requests do. The heartbeat expires after ten seconds.

Hardware effects run on one helper queue. Direct activation admits, acknowledges and targets each fan before moving to the next. Reference adapters support reviewed protected-mode handover where available. Partial failure restores every fan and verifies final ownership. Requests cannot choose fallback keys or clear targets.

Unchanged targets on the tested M5 direct path can renew a lease without rewriting the hardware, after fresh readings and independent target/metadata verification. Other adapters retain their own transaction paths. Idle helper polling is one second; active leases and pending restoration use a 100 ms decision timer, with full watchdog acquisitions paced separately. The responsive health channel publishes completed observations and rejects stale ownership evidence.

## Temperatures and profiles

The signed registry matches the notebook model and chip generation before resolving sensor groups and fan metadata. Selected sensor membership stays fixed for a resolved backend. Missing, stale, corrupt or incorrectly typed required readings block activation or cause handback.

Mac17,9 uses a fixed 105-key chip envelope and separate CPU/GPU regional selections. Other supported notebooks use explicit generation-specific CPU/GPU groups. CPU/GPU display averages are estimates; Top proximity is a chassis proxy. [Compatibility](docs/COMPATIBILITY.md) describes the tested models and remaining limits.

Demand is the maximum of enabled curves, minimum airflow and an optional temperature target. Curves interpolate between ordered points. The target adds proportional demand: 50% at its selected temperature, with full response bands of 20°C for chip, 10°C for trackpad/actuator and 16°C for airflow. It cannot guarantee an attainable temperature.

Fan response applies time-weighted averaging and rate limits. Apple auto at idle can release control while demand is zero. Serious, critical or unknown thermal pressure returns control directly to macOS; there is no separate temperature-triggered maximum-fan override. See [Safety](SAFETY.md).

## Configuration and lifecycle

A revision-aware persistence actor saves profiles, automation and preferences without allowing older writes to replace newer state. Imports validate size, structure, identities and values before publication. Legacy migrations preserve edited profiles and stable built-in identifiers, including `school` for Silent. Runtime leases, RPM targets, process instances and countdowns are never restored from disk.

Startup verifies System ownership before resuming an eligible remembered profile or schedule. System sleep releases control and suspends monitoring, automation and periodic update work. Wake verifies automatic ownership and fresh readings before resuming still-valid intent; time limits keep their original deadlines. System, quit, faults and disconnection revoke in-flight work before restoration. A blocked or dead helper cannot execute its watchdog.

The app uses native menus and lazily hosted editors. Closing a window releases its content graph without stopping background monitoring or automation. Display-only sensors and previews do not grant hardware authority.

## Updates and local diagnostics

Sparkle fetches the fixed HTTPS GitHub appcast and verifies archives with the embedded public Ed25519 key. System profiling is disabled. Before installation, Fandy requires verified fan restoration, saved configuration and removal of the old helper registration. The next launch registers the replacement helper.

Configuration and bounded diagnostic logs remain under Application Support/Fandy. The helper uses macOS unified logging. User-requested diagnostic exports contain an allowlisted summary; configuration exports can contain custom names, schedules and application rules. There is no analytics or automatic log-upload service.

## Verification

`Scripts/verify.sh` runs Swift and Python tests. Its sanitizer and native-build modes cover concurrency/memory checks and unsigned Release compilation. Hardware tests use injected transports; software fixtures do not establish physical compatibility. M2 Pro and M5 Pro have been physically tested by the owner. Live hardware work follows the [hardware testing requirements](docs/HARDWARE_GATES.md).

GitHub retains pull requests and four required checks for main. Documentation and `.gitignore` changes use lightweight Linux checks; source, tests, build resources, signing, tooling and workflow changes run the full macOS suites. Unknown change types and failed change classification cannot select the lightweight path.
