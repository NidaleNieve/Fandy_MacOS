# GitHub release verification

Updated October 5, 2026 for **Fandy 0.2.1** (internal build 11). Release tag `v0.2.1` points to application source `cad933f`. The application and DMG are Developer ID-signed, notarized and stapled. The previous v0.2.0 release remains available. The mislabeled build 10 release was replaced with this matching version, title, tag and artifact.

## Public download

[Release page](https://github.com/NidaleNieve/Fandy_MacOS/releases/tag/v0.2.1) · [DMG](https://github.com/NidaleNieve/Fandy_MacOS/releases/download/v0.2.1/Fandy-0.2.1-arm64.dmg)

The release contains only the notarized DMG. Checksum and verification-report attachments were removed at the owner's request; local verification records remain available for development. Both the versioned download and README's latest-release download were retrieved anonymously and matched the verified local image.

The image contains Fandy.app and an Applications shortcut; the project's MIT license and required third-party notices are inside the application. Settings reads the version directly from the installed app's bundle metadata. The image contains no personal profiles, schedules, logs, measurements, signing configuration or debug symbols.

## Validation and limits

- The final 0.2.1 sources passed 394 Swift tests, 48 tool tests and signed arm64 Release compilation. The prior nine focused Thread Sanitizer tests are retained; fan-control code did not change for this version/settings/resource update. Staged privacy checks pass.
- The final app and image use **Developer ID Application** signing. Matching app/helper identities, hardened runtime and payload privacy pass the packaging verifier.
- App and DMG notarization tickets are stapled and validate successfully. App execution and image-opening Gatekeeper assessments pass. Disk-image integrity and read-only mounted contents pass verification; the mounted app reports version 0.2.1, build 11, and contains the MIT license. Anonymous versioned and latest downloads match SHA-256 `67d81528420a9c82b5740f3e27bae469070371d58497520b67c0fb43e825d8aa`.
- M5 Pro fan-control evidence is local. Other M1–M5 MacBook Pro support is reference-derived and subject to runtime metadata/sensor checks. This release does not establish physical compatibility on inaccessible Macs.
- Apple certificates necessarily disclose the signer identity; the owner accepted that disclosure. Private signing configuration and credentials remain outside Git.
- The current root-helper/undocumented SMC architecture is not cleared for the Mac App Store. See [the assessment](APP_STORE_READINESS.md).

## Privacy audit

Before initial publication, all 38 reachable Git commits and 629 unique blobs were scanned, including historical content and commit identities. No private-source/history findings were detected. No history rewrite was necessary. Git authors use a project identity, and third-party license attribution remains intact. Subsequent publication updates also pass the staged public-content checker.

## Repository presentation and license

The repository description identifies native Apple Silicon fan control, curves, schedules and live temperatures. The README and description include the owner's requested wording: "Vibecoded with Codex, but very polish." The original project is now MIT-licensed in the root `LICENSE`, and GitHub's license metadata reports MIT. Third-party attributions and their license texts remain intact. Public README, license and third-party notice contents match the local committed files.

## Screenshots

The README uses the owner's supplied screenshots of Cool Chassis: its chip curve editor and native menu with live temperature readings. Rounded corner masks preserve the original screenshot content and resolution; the menu's surrounding desktop margin is cropped. No personal information or schedules are visible. PNG ancillary metadata was stripped, and both images were visually reviewed.

The public-content checker permits only specifically reviewed image paths and validates PNG structure, checksums and allowed non-text chunks. Other binary artifacts remain rejected. The images are shown side by side at the same display height, with the updated menu screenshot at a readable size and a subtle RGB 197, 197, 197 outline around the rounded curve image. Customizable temperature readings inside the menu are documented explicitly.

## Remaining work

Collect installation and hardware feedback from other MacBook Pro models. Reference support remains distinct from physical testing. Resolve the App Store architecture blockers before preparing a Store submission. Existing physical sleep/wake and subjective calibration follow-ups remain; notarization does not replace them.

This publication did not replace the running app, change user profiles or helper permissions, or issue fan commands.
