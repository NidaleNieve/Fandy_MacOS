# Distribution pipeline

The release app and helper retain is.dsr.fandy / is.dsr.fandy.fan-helper and the existing signing team. Public source contains no signing team configuration, passwords, certificates, measurements or personal settings.

A development-signed image can be produced with `python3 Scripts/package-dmg.py`. It is unnotarized and not Gatekeeper-ready.

## One-time notarization setup

1. In **Xcode → Settings → Accounts**, select your paid developer account/team, open **Manage Certificates…**, click **+**, and create **Developer ID Application**. Use the same team as the existing app and helper. Apple requires the Account Holder role for local Developer ID certificates; see [certificate guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).
2. At [account.apple.com](https://account.apple.com), create an **app-specific password** under **Sign-In and Security**. See [Apple's instructions](https://support.apple.com/en-us/102654).
3. From Terminal, run the command below. Enter your Apple Account, Team ID and app-specific password in its interactive prompts. Credentials are stored in the local Keychain, not in Git or the app.

```sh
xcrun notarytool store-credentials "FandyNotary"
```

Do not paste the password into chat, repository files or command-line arguments.

## Build and notarize

```sh
FANDY_BUILD_CONFIGURATION=Release Scripts/build.sh -jobs 1
python3 Scripts/distribute.py --keychain-profile FandyNotary
```

The script signs the helper and app, notarizes and staples both the app and DMG, and checks Gatekeeper and the final mounted payload. It requires exactly one valid Developer ID Application identity and preserves the trusted team. Output is `build/Distribution-Release/Fandy-VERSION-arm64.dmg`, its checksum and `verification.json`. It creates no verified release on failure and does not upload to GitHub. Use a new `--output` directory if that output already exists.

The DMG contains Fandy.app and an Applications shortcut, with license notices inside the app. Private settings, logs and signing configuration are excluded. Developer ID builds require installation in Applications before helper registration. Verify the genuinely distribution-signed app/helper connection and automatic restoration through normal installation before replacing the public release; the current live evidence uses Apple Development signing.

Verify software with `Scripts/verify.sh`, or run the unsigned native compile check with `FANDY_BUILD_CONFIGURATION=Release Scripts/verify.sh --native-build`. CI adds macos-15 and macos-latest native Release compilation. CI results and actual runtime checks must be reported separately.

References: [Apple Developer ID distribution](https://developer.apple.com/developer-id/), [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Build credentials remain exclusively local. A paid membership alone does not install the required distribution certificate or establish notarization credentials.
