# Fandy 0.2.3 update integration

Version **0.2.3**, replacement release build **18**, adjusts update controls, repairs an enabled but unreachable helper registration after app replacement, and includes the quieter School factory curve. Frequency is editable when automatic updates are on, disabled when off. Turning automatic updates off stops scheduled checks/downloads; manual checking remains available. Updates appears immediately above Configuration Files, with the current version there and a subdued footer at the bottom right.

An accepted native update offer downloads and installs without a second ready-to-install confirmation. Background downloads retain install-on-quit and a two-week reminder; Settings also offers Install Update for a staged download. Fandy retains Sparkle’s documented immediate-install callback while that download waits, and owns its native reminder prompt; manual checks remain available and show the staged offer. Every installation still requires sensor-independent fan restoration and verified helper acknowledgement, saved configuration, and removal of the old helper registration before app replacement.

## Verification

- 409 Swift tests: 53 hardware, 210 core, 146 application tests, including accepted-download handling, update preference policy, approval presentation and School migration without overwriting tuned profiles.
- 52 Python tool tests.
- A signed isolated fixture uses the production update driver to manually check, accept the offer, download and replace its app without a second confirmation. The native installer completes and crosses the normal quit boundary. No fan helper or production preferences are present in this fixture.
- The previously verified tampered-archive rejection and helper-safety tests remain in the test suite. Updated native rejection and live helper checks are recorded below as they complete.

## Helper recovery

Startup now waits for registration to finish before interpreting its approval status. Automatic setup requires a continuously observed `requiresApproval`; an already enabled registration exits without a guide or System Settings window. The menu's Allow Fan Control action opens the dedicated guide and the native Login Items & Extensions page together. Numbered instructions remain separate rows, and a small red dot beside the menu-bar icon identifies missing approval. The guide closes only after approval is observed, not because registration is temporarily in progress. These changes affect presentation, not helper authentication or fan-control authority.

Observed failure on the installed 0.2.2 app: launchd repeatedly returned EX_CONFIG while failing to resolve BundleProgram despite the helper file and approval being present. The registration appeared enabled. The decisive launchd trace confirms a launch-constraint violation: the cached requirement demanded Apple Development validation category 3, but the distributed helper has Developer ID category 6. Unregister/register did not clear the legacy constraint. Startup now unregisters the legacy service before registering the distinct distribution label `is.dsr.fandy.fan-service`. The helper signing identity and Mach service remain `is.dsr.fandy.fan-helper`. The signed bundle retains the old plist solely for removal. The new plist also supplies an explicit executable argument vector. This follows Apple's documented launchd arguments and the constraint behavior discussed in [Apple's developer forum](https://developer.apple.com/forums/thread/795022).

For an already-current but unreachable service, startup attempts one ServiceManagement unregister/register only after an unavailable XPC response from an enabled genuine service. It first attempts automatic release and blocks activation until fresh helper status independently confirms restoration. This repair does not bypass authentication or hardware authority, and does not repeatedly fight disabled services or another controller.

A dead or blocked helper cannot run its watchdog. Rebinding starts a replacement helper, whose startup restoration remains the recovery boundary; it is never reported as verified solely because registration succeeded.

## Release and live test

A local Release baseline and a higher-build GitHub release exercise actual replacement, helper startup recovery and a Settings-initiated check. The DMG must be Developer ID signed, notarized and stapled before publication. Checksums and verification reports stay local; the public release contains only the DMG. Live user interaction is marked pending until the user checks and accepts the offered update.

Use the repository owner's configured Git identity for every commit. Update Info.plist and FandyBuild together. Keep private keys, notary credentials, measurements and personal schedules out of source and releases.

## Local helper observations

The notarized migration baseline (build 14) removed the old job and started the distribution service with validation category 6. Authenticated status reported helper build 14, complete sensor data, no fault and verified per-fan startup restoration. The saved ordinary profile resumed. A normal quit then produced a verified manual-mode 1 to automatic-mode 0 transition on each fan; a separate read-only process confirmed both modes remained 0. Reopening retained a running authenticated helper. Raw evidence stays in ignored local build files.

GitHub-driven baseline-to-release installation remains a user-interaction acceptance check: the user will initiate Check for Updates in Settings and accept the native offer. Do not describe that pending acceptance as already tested.

The pending-install fixture initially reached termination but stalled inside the kernel's rename operation. Fresh temporary locations and a non-atomic fixture fallback did not resolve the unnotarized fixture failure. With both fixture versions notarized and Gatekeeper-accepted, the unchanged production install callback successfully replaced build 11 with build 12. This verifies the signed distribution path; it does not establish the exact macOS cause of the earlier stall. Fixtures use unique bundle identities and have no fan helper or production preferences.

## Distribution verification

The original Release build (15) and 404 Swift / 52 tool tests passed, followed by 409 Swift tests and signed local builds covering the approval fixes. The user's original GitHub update reached an enabled, running helper but exposed the now-fixed startup approval race. Local build 17 remains installed for the replacement build 18 updater check. Restored local Keychain credentials enabled app and DMG notarization. Release publication requires both to be stapled and Gatekeeper, embedded signatures, mounted payload privacy and image integrity checks to pass. Credentials and verification manifests remain local.

Both notarized native fixture tests pass. The staged test downloaded the signed archive, retained the supported immediate-install handler, crossed normal termination and replaced the application successfully without another confirmation. The manual test accepted the initial offer, passed through the production ready-to-install driver without a second confirmation, terminated and replaced build 11 with build 12. Run `python3 Scripts/test-updater.py --install-pending --notarize-fixture` or `--manual --notarize-fixture` respectively. The real GitHub update and post-update helper startup remain the final user-interaction check, separate from isolated installer tests.
