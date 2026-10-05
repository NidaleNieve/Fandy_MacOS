# Distribution pipeline

The release app and helper retain is.dsr.fandy / is.dsr.fandy.fan-helper and the existing signing team. Public source contains no signing team configuration, passwords, certificates, measurements or personal settings.

A development-signed image can be produced with `python3 Scripts/package-dmg.py`. It is unnotarized and not Gatekeeper-ready.

## Reuse saved credentials

Normal releases reuse the local `FandyNotary` Keychain profile automatically. The release script checks it before signing; it does not delete or recreate credentials. Use the default Keychain lookup. Specify `--keychain PATH` only for a profile deliberately stored in that Keychain. A failed lookup does not mean you need a new password.

Signing Team IDs remain in ignored per-target `.local.xcconfig` files and survive project regeneration. Keep these local files when switching branches.

## One-time notarization setup

1. In **Xcode → Settings → Accounts**, select your paid developer account/team, open **Manage Certificates…**, click **+**, and create **Developer ID Application**. Use the same team as the existing app and helper. Apple requires the Account Holder role for local Developer ID certificates; see [certificate guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).
2. At [account.apple.com](https://account.apple.com), create an **app-specific password** under **Sign-In and Security**. See [Apple's instructions](https://support.apple.com/en-us/102654).
3. From Terminal, run the command below. Enter your Apple Account, Team ID and app-specific password in its interactive prompts. Credentials are stored in the local Keychain, not in Git or the app.

```sh
xcrun notarytool store-credentials "FandyNotary"
```

Do not paste the password into chat, repository files or command-line arguments. This is one-time setup, not a step for each release. Apple revokes app-specific passwords after a primary Apple Account password reset; that server-side revocation requires replacement credentials.

## Build and notarize

```sh
FANDY_BUILD_CONFIGURATION=Release Scripts/build.sh -jobs 1
python3 Scripts/distribute.py
```

The script signs the helper and app, notarizes and staples both the app and DMG, and checks Gatekeeper and the final mounted payload. It requires exactly one valid Developer ID Application identity and preserves the trusted team. Output is `build/Distribution-Release/Fandy-VERSION-arm64.dmg`, its checksum and `verification.json`. It creates no verified release on failure and does not upload to GitHub. Use a new `--output` directory if that output already exists.

The DMG contains Fandy.app and an Applications shortcut, with license notices inside the app. Private settings, logs and signing configuration are excluded. Developer ID builds require installation in Applications before helper registration. Developer ID app/helper startup and automatic restoration have been verified on the available M5 Pro. Other-machine installation acceptance remains separate from packaging verification. Authentication admits the matching signed identifier and team for both signing classes.

Verify software with `Scripts/verify.sh`, or run the unsigned native compile check with `FANDY_BUILD_CONFIGURATION=Release Scripts/verify.sh --native-build`. CI adds macos-15 and macos-latest native Release compilation. CI results and actual runtime checks must be reported separately.

References: [Apple Developer ID distribution](https://developer.apple.com/developer-id/), [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Build credentials remain exclusively local. A paid membership alone does not install the required distribution certificate or establish notarization credentials.

## Update releases

The first updater-enabled version is 0.2.2. Older versions need one manual install.

The updater key is an Ed25519 key in the local Keychain account `is.dsr.fandy`. Only its public key is embedded in Info.plist. Keep the private key for future releases; losing it prevents existing installations from trusting new archives. Generate it once with Sparkle’s `generate_keys --account is.dsr.fandy` and retain its license notices.

Release order:

1. Increment the app version/build and `FandyBuild` together. Run Swift and tool tests, then the signed Release build.
2. Notarize and staple the app and final DMG with `Scripts/distribute.py`. Check the mounted payload, Gatekeeper and local verification report.
3. Generate the appcast with Sparkle’s `generate_appcast --account is.dsr.fandy --download-url-prefix https://github.com/NidaleNieve/Fandy_MacOS/releases/download/vVERSION/ ARCHIVES_DIR`. Sign the final stapled archive, never an earlier DMG.
4. Verify signatures, upload the DMG to a draft GitHub release, publish the release, then publish the appcast to the `updates` branch. Retain previous entries for older macOS versions. A failed notarization or signature check blocks publication.

Only the DMG is a release attachment; checksums and verification reports stay local. The updater fetches the fixed HTTPS raw GitHub feed, follows GitHub’s archive redirects, and sends no sensor or profile data.

For the isolated real Sparkle test, unpack the pinned official Sparkle tools into `build/SparkleTools`, then run `python3 Scripts/test-updater.py` and `python3 Scripts/test-updater.py --corrupt`. A local HTTP feed is limited to this fixture; production uses HTTPS. The fixture has its own bundle/defaults identity, no helper and no fan writes. Pure clock tests cover weekly checks and the two-week reminder without wall-clock waiting. Native archive tests cover replacement on quit and signature rejection; they do not establish a two-week elapsed runtime observation.
