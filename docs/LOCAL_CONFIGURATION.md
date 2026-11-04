# Building locally

Use Xcode with Swift 6 support on Apple Silicon and macOS 15 or later. Build and test commands are in the [README](../README.md).

## Signing

Set your team in the ignored `Config/Signing.local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Defaults use automatic Apple Development signing. Keep the app/helper identifiers `is.dsr.fandy` and `is.dsr.fandy.fan-helper`; they authenticate the matching team and peer identity.

`Scripts/generate-project.py` preserves Xcode signing selections in ignored per-configuration `*.local.xcconfig` files under `Config/Signing/`. Keep these when switching branches. Regenerate the project before committing Xcode signing edits.

For live control, quit other copies, install the signed build at `/Applications/Fandy.app`, and approve Background App Activity. Follow [Hardware testing](HARDWARE_GATES.md) before physical writes. Unsigned builds check compilation only.

## Repository checks

Builds, logs, measurements, credentials and local signing files are ignored. Keep private notes in `docs/local/` or `private/`; root `AGENTS.md` is local too.

Enable the staged-content check:

```sh
git config --local core.hooksPath .githooks
python3 Scripts/check-public-content.py --staged
```

It checks for private paths, signing details, common credentials and unreviewed binaries. Review staged content as well.

Pull requests target `main`. Documentation and `.gitignore` changes use lightweight checks. Code, tests, build resources, signing, tools and workflow changes run the full macOS verification suites.
