# Release UI and activation fixes — 2026-10-04

Version 0.2.0 build 6 implements the latest setup, activation, window, menu and settings corrections. The privileged helper interface and fan transactions are unchanged.

## Behavior

Setup shows the System Settings → General → Login Items & Extensions → Background App Activity path, without announcing that the window closes. Approval still closes the dedicated setup window automatically.

A profile with an application-close condition can be manually selected before that application runs. It waits for the first observed instance, then watches that exact PID/start time and ends when it closes. Switching profiles, cancelling, faults and sleep clear the pending watch. This runtime watch is never persisted. Until Changed can replace the pending watch with an explicit pin, and a second selection unpins it. Automatic launch rules continue to require an actual newly observed application launch.

Long Cancel / Resume Schedule actions show their full text in a bounded multiline row with rounded hover highlighting; the underlying native title remains bounded so AppKit cannot widen the menu. Accessibility and tooltip retain the full action. Fan monitoring and chosen temperatures stay centered inside the menu. The status-bar button displays the fan icon alone. Fan bar and percentage/RPM visibility have separate settings, default on; the profile monitoring sidebar retains its own readouts.

Profiles starts at 1040×720, with a reduced 780×480 minimum. Both sidebar dividers are native, adjustable and noncollapsing. Sidebar backgrounds use system material; table backgrounds are transparent. The section picker falls back to a native menu when the editor is narrow, preventing width overflow. Hidden-scroll-indicator and hosting-sizing protections remain.

Settings puts keyboard shortcuts before configuration files, maintenance/export diagnostics at the bottom, and adds a confirmed Reset to Defaults action. Reset replaces custom profiles, schedules, activation conditions, shortcuts and preferences with built-ins/defaults, returns to System, clears profile undo history, and exits simulation. It does not erase macOS permission records. Launch-at-login explanatory text is removed. Simulation explicitly describes simulated temperatures/fans and disabled physical control. The shortcut label is Open Menu; its existing open/close behavior remains.

## Verification

371 Swift tests pass: 48 hardware, 191 core and 132 app. 46 Python tool tests pass. Coverage includes absent-application manual activation, stale process identity at launch, waiting-watch pin conversion, wrapped action width/accessibility, both native dividers, reduced native window bounds, old preference decoding, portable fan-visibility settings, and persisted reset defaults. Existing helper authentication, watchdog, restoration, scheduling, persistence and curve tests remain passing.

A signed, one-job arm64 Release build succeeds. The signed bundle's isolated simulation functional check passes five ticks in System. This is a software check, not physical fan or M1 verification. No helper installation, approval changes, screenshots or GUI automation were performed for these changes. Background App Activity remains under the user's control.

## Package

`build/Distribution/Release-0.2.0-build6/Fandy-0.2.0-arm64.dmg`

SHA-256: `21ec6aad91e88ba3709b8ac7a66347d6e6add7eb0b312abf22a7a51e39801ef9`.

The DMG contains only Fandy.app and an Applications shortcut. Embedded license notices remain. App/helper signatures, matching identity/team, hardened runtime, absence of debug entitlements, payload privacy, DMG integrity and read-only mounted contents pass. The filename no longer contains Test. It remains Apple Development-signed and unnotarized; renaming does not change signing trust. Developer ID/notarization and actual M1 permission/hardware testing remain follow-ups.
