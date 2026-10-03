# Inline menu and test DMG — 2026-10-03

Git was already initialized and connected to the project remote. A clean baseline was checkpointed on branch `codex/inline-menu-dmg` before implementation changes.

## Interface

Other Time/Until and While App Is Running are actual hover-open `NSMenu` submenus. Each embeds its editable controls through `NSMenuItem.view` and `NSHostingView`; there is no extra Choose item, popover, separate window, application activation or synthetic menu reopening. Time controls retain For/Until, exact fields, selectable clock and time-format preference. The app list retains native search, icons, refresh, and the helper/process toggle. Successful selection ends menu tracking normally. Native profile and minute/hour actions still follow AppKit's normal dismissal behavior.

The fan bar and percentage/RPM are centered as a group. The readout's hosting view has width autoresizing, allowing AppKit to expand it across the native menu width rather than leaving it at the left of the state/shortcut columns. Text stays bounded and wraps. The bar remains 120 by 3 points; actual per-fan readings are still displayed in System and other profiles. The current-information column in Profiles keeps its own existing leading alignment.

Profiles sidebar and main editor/current column hide scroll indicators while retaining scrolling. Native selection/double-click behavior, protected built-ins, adjustable non-collapsible split view, profile undo, schedules and fan safety are unchanged.

## Verification

- 314 Swift tests pass: 28 hardware, 190 core, 96 app, one job with no parallel tests.
- 37 tool tests pass, including four packaging tests covering metadata/identity rejection, private payload rejection, external links/debug symbols and failed-preflight behavior.
- Native menu regressions verify hover submenu structure, embedded view identifiers and bounded sizes, readout expansion, normal hour/minute rows and compact root-menu bounds.
- Signed single-job Release build succeeds. App and helper retain the existing identifiers and signing team, hardened runtime and no debugging entitlement.
- Release compilation maps source/debug paths. Xcode strips local/debug Mach-O symbols before signing; separate dSYMs are not packaged. The first preflight correctly rejected unstripped developer object-file paths, and the rebuilt payload passes.
- The compressed DMG passes `hdiutil verify`. Its read-only mounted copy passes app/helper signature, team, architecture and private-path/file checks. Only Fandy.app, an Applications symlink and a concise Read Me are included.
- The installed Debug-to-Release update first restored both fans and unregistered the helper. Overlay copying left the previous preview/debug libraries behind, so signature verification correctly blocked restarting it. Removing those two obsolete files restored the signed Release payload; normal ServiceManagement registration then succeeded. Future mixed-configuration installs should replace the complete bundle rather than merge it.
- Installed Release startup passes five ticks: real monitoring, qualifiedControl/controlReady, System, Apple ownership, both fan modes 0/0 and no monitoring warning. Helper and login registrations remain enabled.

No screenshots, automated GUI navigation, visual comparison, stress load or manual fan-profile experiment were performed. These checks establish construction, layout/state and packaging behavior; human pointer/keyboard feel and native appearance still require review.

## Rebuild and distribution limits

```sh
FANDY_BUILD_CONFIGURATION=Release Scripts/build.sh -jobs 1
python3 Scripts/package-dmg.py
```

Output is `build/Distribution/Fandy-0.1.0-arm64-Test.dmg`, its `.sha256` checksum and `verification.json`. An existing output is not overwritten; use `--output` to choose another directory. The packager never launches Fandy, registers a helper or issues fan commands. Credentials, certificate owner/team values, raw readings, local profiles, preference files and signing configuration are not written to its report or committed to Git. Valid code signatures retain their certificate metadata by design.

The available certificate is Apple Development. This artifact is a **signed, unnotarized test build**, not a general production distribution: Gatekeeper may prevent opening it on another Mac. A broadly distributable version needs Developer ID Application signing, notarization and stapling, with app/helper identity and authentication reverified. This package introduces no Gatekeeper bypass, root installer or entitlement relaxation. See Apple's [packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) and [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Requires macOS 15+ and Apple Silicon. Current physical control qualification covers only **Mac17,9**. Other Apple Silicon models remain monitoring-only; packaging does not extend hardware authority. On a supported Mac, first installation of the embedded helper still uses ServiceManagement and native Login Items & Extensions approval. Startup/wake stay System-first. No helper state or profiles from the development Mac travel in the image.

Existing unresolved follow-ups remain: physical active sleep/wake review, acoustic/comfort feedback and gaming calibration. A dead/blocked helper cannot execute its watchdog; launchd restart recovery remains the documented fallback.
