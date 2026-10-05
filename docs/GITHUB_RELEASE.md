# GitHub release verification

Fandy **0.2.2** (internal build 12) is Developer ID signed, notarized and stapled. Its release tag is `v0.2.2`; previous releases remain available.

[Release page](https://github.com/NidaleNieve/Fandy_MacOS/releases/tag/v0.2.2) · [DMG](https://github.com/NidaleNieve/Fandy_MacOS/releases/download/v0.2.2/Fandy-0.2.2-arm64.dmg)

The only release attachment is the DMG. It contains Fandy.app and an Applications shortcut, with MIT and third-party license notices inside the app. It excludes personal configuration, logs, measurements, signing credentials and debug symbols. Local checksum and verification reports are retained outside Git.

## Checks

401 Swift tests, 51 tool tests and signed arm64 Release compilation pass. App/DMG notarization tickets, Gatekeeper assessments, mounted contents and payload privacy pass. Native isolated Sparkle tests verify install on quit and tampered-archive rejection; see [update verification](UPDATE_DELIVERY.md). Publication retrieves the public download and update feed and checks them against the verified local artifact before completion.

The fixed HTTPS appcast is published on the `updates` branch after the notarized DMG is available. Update archives are Ed25519 signed; the private key stays in the developer’s Keychain. GitHub receives update requests, but no temperatures, profiles or telemetry are uploaded.

## Attribution and privacy

At the owner’s request, the 13 placeholder-authored commits were reattributed to NidaleNieve using the configured GitHub noreply address. Every rewritten commit retains its original file tree. Branches and release tags retain their source content; hashes change because commit identity is part of the hash. Future commits use that same identity. Private source/signing artifacts stay excluded and third-party license attribution is preserved. Signing certificates necessarily expose the developer identity, as previously accepted by the owner.

The README uses the owner’s supplied, privacy-reviewed screenshots and retains the requested tagline, “Vibecoded with Codex, but very polish.” GitHub identifies the project as MIT licensed.

## Limits

M5 Pro fan behavior is locally tested; other M1–M5 MacBook Pro support is reference-derived and checked at runtime. This release does not establish physical compatibility on inaccessible Macs. The helper/SMC architecture remains unsuitable for the Mac App Store without resolving the [documented blockers](APP_STORE_READINESS.md).

This release work does not replace the running app or alter user profiles or fan-helper permissions.
