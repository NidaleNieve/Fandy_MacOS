# Distribution pipeline

The release app and helper retain is.dsr.fandy / is.dsr.fandy.fan-helper and the existing signing team. Public source contains no signing team configuration, passwords, certificates, measurements or personal settings.

Build with one job:

```sh
FANDY_BUILD_CONFIGURATION=Release Scripts/build.sh -jobs 1
```

A development-signed test image can be produced with `python3 Scripts/package-dmg.py`. Its filename and verification report explicitly say Test / unnotarized. This is not a Gatekeeper-ready release.

For broad distribution, install a Developer ID Application certificate privately through Xcode's account certificate manager. Configure notarytool credentials into a local keychain profile using Apple's documented interactive/keychain workflow. Do not enter secrets in repository files, chat, shell history or command-line arguments. Fandy's normal application and helper never use notarization credentials or network access.

```sh
python3 Scripts/distribute.py --keychain-profile YOUR_LOCAL_PROFILE_NAME
```

The distribution script requires exactly one valid Developer ID Application identity and preserves the existing trusted team. It copies the Release app into temporary staging, signs helper before app with hardened runtime and a secure timestamp, verifies matching identities/architecture, submits an app archive, staples the app, constructs the drag-to-Applications image, signs and submits that image, staples it, verifies both tickets and Gatekeeper assessments, and checks the final mounted payload read-only. The final SHA-256 is computed after stapling. Only then is `build/Distribution-Release/Fandy-VERSION-arm64.dmg` published with its checksum and verification.json. A failed submission cannot publish a verified release. Apple tool output is not printed publicly because it can contain account information.

The DMG contains Fandy.app, an Applications shortcut and concise Read Me instructions. Attribution/license notices are inside the signed app. No debug symbols, raw logs, sensor recordings, signing configuration or developer paths are packaged. Installation into /Applications/Fandy.app is required before helper registration for Developer ID builds; mounted-image and translocated launches cannot register the service. First launch stays System, with native SMAppService approval only when needed.

Verify software with `Scripts/verify.sh`, or run the unsigned native compile check with `FANDY_BUILD_CONFIGURATION=Release Scripts/verify.sh --native-build`. CI adds macos-15 and macos-latest native Release compilation. CI results and actual runtime checks must be reported separately.

References: [Apple Developer ID distribution](https://developer.apple.com/developer-id/), [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Build credentials remain exclusively local. A paid membership alone does not install the required distribution certificate or establish notarization credentials.
