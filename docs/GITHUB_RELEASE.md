# GitHub release verification

Updated October 4, 2026 for **Fandy 0.2.0, build 8**. The release retains tag commit `175270d` and application source `895537d`; subsequent changes cover publication documentation and screenshots. The application was re-signed for Developer ID distribution and notarized.

## Public download

[Release page](https://github.com/NidaleNieve/Fandy_MacOS/releases/tag/v0.2.0) · [DMG](https://github.com/NidaleNieve/Fandy_MacOS/releases/download/v0.2.0/Fandy-0.2.0-arm64.dmg)

The release contains only the notarized DMG. Checksum and verification-report attachments were removed at the owner's request; local verification records remain available for development. Both the versioned download and README's latest-release download were retrieved anonymously and matched the verified local image.

The image contains Fandy.app and an Applications shortcut; required license notices are inside the application. It contains no personal profiles, schedules, logs, measurements, signing configuration or debug symbols.

## Validation and limits

- The application changes passed 375 Swift tests, 46 tool tests and signed arm64 Release compilation. The documentation image-policy changes pass 48 tool tests. The complete Swift suite was not rerun for these documentation-only changes.
- The final app and image use **Developer ID Application** signing. Matching app/helper identities, hardened runtime and payload privacy pass the packaging verifier.
- App and DMG notarization tickets are stapled and validate successfully. App execution and image-opening Gatekeeper assessments pass. Disk-image integrity and read-only mounted contents pass verification; the mounted app reports build 8.
- M5 Pro fan-control evidence is local. Other M1–M5 MacBook Pro support is reference-derived and subject to runtime metadata/sensor checks. This release does not establish physical compatibility on inaccessible Macs.
- Apple certificates necessarily disclose the signer identity; the owner accepted that disclosure. Private signing configuration and credentials remain outside Git.
- The current root-helper/undocumented SMC architecture is not cleared for the Mac App Store. See [the assessment](APP_STORE_READINESS.md).

## Privacy audit

Before initial publication, all 38 reachable Git commits and 629 unique blobs were scanned, including historical content and commit identities. No private-source/history findings were detected. No history rewrite was necessary. Git authors use a project identity, and third-party license attribution remains intact. Subsequent publication updates also pass the staged public-content checker.

## Screenshots

The README uses the owner's supplied screenshots of Cool Chassis: its chip curve editor and native menu with live temperature readings. Rounded corner masks preserve the original screenshot content and resolution; the menu's surrounding desktop margin is cropped. No personal information or schedules are visible. PNG ancillary metadata was stripped, and both images were visually reviewed.

The public-content checker permits only specifically reviewed image paths and validates PNG structure, checksums and allowed non-text chunks. Other binary artifacts remain rejected. The images are shown side by side at the same display height, with the updated menu screenshot at a readable size and a subtle RGB 197, 197, 197 outline around the rounded curve image. Customizable temperature readings inside the menu are documented explicitly.

## Remaining work

Collect installation and hardware feedback from other MacBook Pro models. Reference support remains distinct from physical testing. Resolve the App Store architecture blockers before preparing a Store submission. Existing physical sleep/wake and subjective calibration follow-ups remain; notarization does not replace them.

This publication did not replace the running app, change user profiles or helper permissions, or issue fan commands.
