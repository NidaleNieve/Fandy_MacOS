# Compatibility release verification — 2026-10-04

Version **0.2.0 (2)**, arm64, deployment target macOS 15. The native signed Release build passes on the available Mac17,9 M5 Pro. Local runtime is macOS 27; an older macOS runtime was not available. No M1–M4 or other M5 hardware was available. [Compatibility matrix and source evidence](COMPATIBILITY.md).

## Software verification

- 340 Swift tests pass: 48 hardware, 191 core, 101 app-model/editor tests, one job and no parallel execution.
- 46 Python tool tests pass, including release metadata, notarization rejection and inability to publish a release without a distribution identity.
- New synthetic fixtures cover all five chip generations, variant omission/frozen membership, missing CPU cluster, independent average/maximum groups, differing fan limits, one/two fans, lowercase/uppercase aliases, fpe2/float metadata, protected mode 3, direct/Ftst transaction order, bounded timeout/cancellation, corrupt baseline/metadata, partial writes, failed global clearing and source-supported restart release.
- Existing authentication, malformed commands, watchdog, curves, scheduling/import, persistence and lifecycle tests are retained. Capabilities are compiled; imported configuration cannot grant hardware authority.
- Signed app/helper identity/team, hardened runtime, absence of debug entitlement, arm64-only payload, private paths/files, disk integrity and mounted contents pass packaging validation.
- Native unsigned Release CI jobs are configured for macos-15 and macos-latest, alongside software and sanitizer jobs. These checks are not physical hardware qualification. Initial remote software tests and latest-macOS Release compilation passed. The macOS 15 compiler identified an unannotated AppKit clock coordinator callback; explicit main-actor isolation fixes the older-SDK error. The corrected remote build and sanitizer results are tracked below.

## Local M5 regression

The helper was released, unregistered, replaced with the verified full bundle and registered normally. An immediate registration attempt returned Operation not permitted during unregister cleanup; a later normal retry succeeded. Final replacement waited for cleanup. No system protections or signing requirements were weakened.

The final app passes System startup with five real monitoring ticks, both modes 0/0 and no monitoring warning. System+, Gaming, Cool Chassis, School and a temporary chip-only custom profile pass bounded live activation/independent RPM-mode observation and verified release. Custom target edits, invalid-draft isolation, simulation/real round trip and rapid switching pass. Diagnostics use temporary profiles; personal profile files are preserved. The fixed signed hostile-input/peer checks pass in the initial compatibility build; subsequent changes retain the same authentication/XPC protocol.

| Recovery | Measured final-build return to both mode 0 |
| --- | --- |
| Disconnect | 0.281 s |
| Normal quit | 0.016 s |
| Heartbeat expiry | 10.035 s |
| GUI SIGKILL | 0.022 s, independent read-only observer |

Root-helper SIGKILL was **not repeated** in this session: noninteractive administrator authorization was unavailable and no password was requested/read. Earlier Mac17,9 helper restart evidence is retained; startup now additionally releases before registry sensor resolution, and reference global release is covered by fixtures. Actual Ftst restart recovery on an inaccessible legacy Mac is not physically proven. Physical sleep/wake remains an earlier outstanding test. A dead or blocked helper cannot execute its watchdog.

## Ordinary-use performance

Twenty paced acquisitions and GUI-model polls, ten curve evaluations per acquisition, 400 dispatch-delay probes; no stress workload.

| Measurement | p95 | Maximum |
| --- | --- | --- |
| Selected-key acquisition | 28.133 ms | 28.526 ms |
| Helper status | 34.527 ms | 35.048 ms |
| Profile evaluation | 0.012 ms | 0.012 ms |
| Production monitoring tick | 39.357 ms | 39.537 ms |
| Main-actor dispatch delay during polling | 1.665 ms | 10.237 ms |

The control acquisition reads its frozen selected keys once each; it does not enumerate the whole catalog every tick. Extra raw display discovery is separate. These are local measurements, not performance promises for other Macs.

## Artifact and remaining distribution blocker

The inspected image is `build/Distribution/Compatibility-0.2.0/Fandy-0.2.0-arm64-Test.dmg`, approximately 1.8 MB, **Apple Development signed and unnotarized**. The verification.json and checksum are beside it. This is explicitly a test artifact; it is not a Gatekeeper-ready deliverable.

SHA-256: `ce2730e6f6a5eb0f5f52e49e1255383e8d5463deb7d0fe10d004b8ba35ae9424`.

There is no valid Developer ID Application certificate installed in the local signing inventory, and no notarization keychain profile has been supplied. Paid membership alone does not supply either. The complete app+DMG signing/notarization/stapling pipeline is ready in Scripts/distribute.py, fails before publishing on absent identity/rejected notarization, and preserves the existing signing team. Configure the certificate and local keychain profile privately, then follow [Distribution](DISTRIBUTION.md). No credential, team configuration, raw measurement or personal profile is committed.

Broad source compatibility is implemented. A notarized release, current root-helper crash retest, physical sleep/wake, and physical M1–M4 validation are not claimed complete. Unsupported metadata/required inputs keep Apple ownership and explain the unavailable profile. Calibration feedback on other machines remains unknown; no tuning, power changes or fan-floor claims were introduced.
