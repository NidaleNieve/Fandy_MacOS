# GitHub release verification

Published October 4, 2026 as Fandy 0.2.0, build 8, tagged at `10c090b`. The release uses the tested application from source commit `63267a4`; subsequent publication changes add documentation and static SVG illustrations only.

## Public download

[Release page](https://github.com/NidaleNieve/Fandy_MacOS/releases/tag/v0.2.0) · [DMG](https://github.com/NidaleNieve/Fandy_MacOS/releases/download/v0.2.0/Fandy-0.2.0-arm64.dmg)

The assets include the DMG, its SHA-256 checksum and a machine-readable verification report. All three were downloaded anonymously from the public release and matched their local SHA-256 hashes. The README's latest-release direct download was independently checked. The DMG is 2,116,364 bytes.

The image contains Fandy.app and an Applications shortcut; required license notices are inside the application. It contains no personal profiles, schedules, logs, measurements, signing configuration or debug symbols.

SHA-256:

```text
5e113e56ff60b4dac04a84162405b91de3bf4366967b111bb70320842993ed84
```

## Validation and limits

- 375 Swift tests and 46 tool tests passed for the application changes.
- A signed arm64 Release build, matching app/helper identities, hardened runtime, absence of debug entitlements, payload privacy, image integrity and read-only mounted contents were verified.
- M5 Pro fan-control evidence is local. Other M1–M5 MacBook Pro support is reference-derived and subject to runtime metadata/sensor checks. This release does not establish physical compatibility on inaccessible Macs.
- The image is Apple Development-signed and **unnotarized**. Its certificate necessarily contains the developer identity; the owner accepted that disclosure. Developer ID signing and notarization remain necessary for smooth public installation.
- The current root-helper/undocumented SMC architecture is not cleared for the Mac App Store. See [the assessment](APP_STORE_READINESS.md).

## Privacy audit

Before publication, all 38 reachable Git commits and 629 unique blobs were scanned, including historical content and commit identities. No private-source/history findings were detected. Newly added publication documents and illustrations also pass the public-content checker across all 189 staged text files. Git authors use a project identity, and third-party license attribution remains intact.

No history rewrite was necessary. The audit intentionally preserves the public project/domain identifiers and legally required third-party credits. Apple certificate identity is the explicit distribution exception; private signing configuration and credentials remain outside Git.

## Next distribution work

1. Configure a Developer ID Application certificate and notarization credentials privately, then rebuild, notarize, staple and assess the image using the existing distribution script.
2. Collect real installation and hardware feedback from other MacBook Pro models; do not convert reference support into a physical-testing claim without observations.
3. Resolve the App Store architecture blockers before preparing a Store archive or claiming Store readiness.

This publication did not replace the running app, change user profiles or permissions, or issue fan commands.
