# Fandy 0.2.3 update integration

Version **0.2.3**, release build **15**, adjusts update controls, repairs an enabled but unreachable helper registration after app replacement, and includes the quieter School factory curve. Frequency is editable when automatic updates are on, disabled when off. Turning automatic updates off stops scheduled checks/downloads; manual checking remains available. Updates appears immediately above Configuration Files, with the current version there and a subdued footer at the bottom right.

An accepted native update offer downloads and installs without a second ready-to-install confirmation. Background downloads retain install-on-quit and a two-week reminder; Settings also offers Install Update for a staged download. Fandy retains Sparkle’s documented immediate-install callback while that download waits, and owns its native reminder prompt; manual checks remain available and show the staged offer. Every installation still requires sensor-independent fan restoration and verified helper acknowledgement, saved configuration, and removal of the old helper registration before app replacement.

## Verification

- 404 Swift tests: 53 hardware, 210 core, 141 application tests, including accepted-download handling, update preference policy and School migration without overwriting tuned profiles.
- 52 Python tool tests.
- A signed isolated fixture uses the production update driver to manually check, accept the offer, download and replace its app without a second confirmation. The native installer completes and crosses the normal quit boundary. No fan helper or production preferences are present in this fixture.
- The previously verified tampered-archive rejection and helper-safety tests remain in the test suite. Updated native rejection and live helper checks are recorded below as they complete.

## Helper recovery

Observed failure on the installed 0.2.2 app: launchd repeatedly returned EX_CONFIG while failing to resolve BundleProgram despite the helper file and approval being present. The registration appeared enabled. The decisive launchd trace confirms a launch-constraint violation: the cached requirement demanded Apple Development validation category 3, but the distributed helper has Developer ID category 6. Unregister/register did not clear the legacy constraint. Startup now unregisters the legacy service before registering the distinct distribution label `is.dsr.fandy.fan-service`. The helper signing identity and Mach service remain `is.dsr.fandy.fan-helper`. The signed bundle retains the old plist solely for removal. The new plist also supplies an explicit executable argument vector. This follows Apple's documented launchd arguments and the constraint behavior discussed in [Apple's developer forum](https://developer.apple.com/forums/thread/795022).

For an already-current but unreachable service, startup attempts one ServiceManagement unregister/register only after an unavailable XPC response from an enabled genuine service. It first attempts automatic release and blocks activation until fresh helper status independently confirms restoration. This repair does not bypass authentication or hardware authority, and does not repeatedly fight disabled services or another controller.

A dead or blocked helper cannot run its watchdog. Rebinding starts a replacement helper, whose startup restoration remains the recovery boundary; it is never reported as verified solely because registration succeeded.

## Release and live test

A local Release baseline and a higher-build GitHub release exercise actual replacement, helper startup recovery and a Settings-initiated check. The DMG must be Developer ID signed, notarized and stapled before publication. Checksums and verification reports stay local; the public release contains only the DMG. Live user interaction is marked pending until the user checks and accepts the offered update.

Use the repository owner's configured Git identity for every commit. Update Info.plist and FandyBuild together. Keep private keys, notary credentials, measurements and personal schedules out of source and releases.

## Local helper observations

The notarized migration baseline (build 14) removed the old job and started the distribution service with validation category 6. Authenticated status reported helper build 14, complete sensor data, no fault and verified per-fan startup restoration. The saved ordinary profile resumed. A normal quit then produced a verified manual-mode 1 to automatic-mode 0 transition on each fan; a separate read-only process confirmed both modes remained 0. Reopening retained a running authenticated helper. Raw evidence stays in ignored local build files.

GitHub-driven baseline-to-release installation remains a user-interaction acceptance check: the user will initiate Check for Updates in Settings and accept the native offer. Do not describe that pending acceptance as already tested.

The pending-install fixture initially reached termination but stalled inside the kernel's atomic rename operation under Documents, confirmed by a one-second installer sample. Fixtures now run in a fresh `/private/tmp` directory with unique bundle identities; no production defaults or fan helper are present. This separates filesystem/fixture interference from updater lifecycle failures.

## Remaining release acceptance

The final Release build (15) and 404 Swift / 52 tool tests pass. The installed notarized build 14 has the working migration and updated settings/School defaults. Final-build notarization is blocked because `notarytool` reports no Keychain password item for `FandyNotary`; credentials must be restored interactively and never committed.

Staged native fixture attempts reached a valid install callback and normal termination, but replacement remained blocked inside a filesystem rename. A fresh temporary location and the supported non-atomic fixture fallback did not resolve this. Generic atomic exchange of empty temporary directories succeeds. Thus the failure is isolated to the fixture app replacement, with cause still unresolved; it is not yet a verified production update. Do not publish the release/feed or ask the user to test it until notarization and the remaining installer acceptance are satisfied. Keep existing v0.2.2 public assets unchanged.
