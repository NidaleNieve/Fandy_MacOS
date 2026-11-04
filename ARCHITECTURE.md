# Architecture

Fandy has a menu-bar app and a privileged fan helper. The app chooses a profile; the helper validates and applies fan commands. Configuration and diagnostics stay on the Mac. Sparkle handles updates.

## Code layout

| Target | Responsibility |
| --- | --- |
| `FandyApp` | AppKit menus and windows, SwiftUI editors, automation and updates. |
| `FandyCore` | Profiles, curves, schedules, persistence and controller rules. |
| `FandyHardware` | Model registry, sensor reads, fan metadata and transaction adapters. |
| `CSMC` | AppleSMC read/enumeration and HID temperature bridge. |
| `FandyHelper` | Root service for authenticated commands, writes, restoration and watchdog. |
| `FandyDiscovery`, `FandyMeasurement` | Development tools, excluded from the app bundle. |

`Package.swift` defines the targets and tests. `Fandy.xcodeproj` assembles the app, helper, Sparkle, generated icon and license notices. Regenerate it with `Scripts/generate-project.py`; local signing settings are preserved.

## App and helper

The app installs at `/Applications/Fandy.app`. ServiceManagement registers its embedded `is.dsr.fandy.fan-control-v2` daemon after Background App Activity approval. App and helper signatures must have matching teams, signing classes and expected identifiers. Each XPC peer authenticates the other.

The interface accepts bounded, versioned JSON for status, leases and targets, plus automatic restoration. The old qualification endpoint is disabled in production. Hardware work runs on one serial queue. Two older daemon plists remain bundled for upgrade cleanup, which requires verified handback before removing a reachable controller.

## Control loop

Manual selections, temporary overrides, application rules and schedules resolve to a profile. `ControlMachine` checks readings and eligibility; `FanXPCClient` requests a connection-owned lease. The helper rechecks sensors, fan bounds, ownership and thermal pressure before applying targets.

Temperature profiles need five healthy acquisitions before activation. Max needs a fresh fan snapshot and uses each fan's maximum. Accepted target requests renew the ten-second lease; status reads do not. Generations and cancellation tokens reject stale work after a switch, disconnect or System request.

Each fan is admitted, acknowledged and targeted before the next fan. Reference adapters handle protected firmware modes through bounded handover. Failure triggers restoration and final mode readback. On the M5 direct path, unchanged targets can renew a lease after fresh verification without another write.

Idle polling runs once a second. Active leases and pending restoration use a 100 ms decision timer, with full watchdog reads paced separately. The health channel serves completed observations and marks stale ownership data invalid. See [Safety](SAFETY.md) for cooling behavior and recovery limits.

## Profiles and state

Sensor groups come from the compiled model registry and stay fixed for a resolved backend. [Compatibility](docs/COMPATIBILITY.md) covers models, input groups and sensor estimates.

Curve drafts remain separate from validated profiles. Built-in definitions and factory migrations live in `BuiltInProfiles`; user edits and stable IDs survive upgrades. The persistence actor serializes saves and rejects obsolete revisions. Imports validate size, structure, identities and values before publication.

Profiles, automation and preferences are saved. Leases, RPM targets, process instances and countdowns are runtime state. Startup verifies System ownership before resuming an eligible profile. Sleep releases control and pauses background work. Wake checks ownership and fresh readings before resuming valid intent, keeping its original deadline.

The app lazily hosts editors and releases their content when windows close. Closing an editor leaves monitoring and automation running. Display sensors and previews stay outside the write path.

## Updates and diagnostics

Sparkle reads the HTTPS GitHub appcast and verifies downloads with the embedded Ed25519 public key. System profiling is disabled. Installation waits for verified fan handback, saved configuration and removal of the old helper registration.

Profiles and bounded logs live in Application Support/Fandy; the helper uses macOS unified logging. Diagnostic exports contain structured status. Configuration exports also include names, schedules and application rules. Logs and readings are not uploaded automatically.

Build and verification commands are in [Building locally](docs/LOCAL_CONFIGURATION.md). Live tests follow [Hardware testing](docs/HARDWARE_GATES.md).
