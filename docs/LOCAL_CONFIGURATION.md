# Building locally

Use Xcode with Swift 6 support on Apple Silicon and macOS 15 or later. The [README](../README.md) contains the build and test commands.

## Signing

Set your development team in an ignored `Config/Signing.local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Public settings use automatic Apple Development signing. The app and helper retain the identifiers `is.dsr.fandy` and `is.dsr.fandy.fan-helper`; the helper authenticates the matching signing team and app identity.

`Scripts/generate-project.py` preserves Xcode signing selections in ignored per-configuration `*.local.xcconfig` files under `Config/Signing/`. Keep those files when regenerating the project or switching branches. Run the generator before committing changes to Xcode signing selections so personal settings stay out of the project file.

For physical fan control, quit other copies and install the signed build as `/Applications/Fandy.app`. Approve Background App Activity through Fandy's setup window. An unsigned CI build checks compilation and cannot establish helper authentication or physical operation. Follow the [hardware testing requirements](HARDWARE_GATES.md) before live tests.

## Local files and checks

Build output, measurements, logs, credentials and local signing files are ignored. Keep private notes under `docs/local/` or `private/`. Local agent instructions can remain in the ignored root `AGENTS.md`.

Enable the public-content check for commits:

```sh
git config --local core.hooksPath .githooks
python3 Scripts/check-public-content.py --staged
```

The check scans indexed contents for private paths, signing identifiers, common credentials and unreviewed binary artifacts. It complements manual review. Retain the project license, third-party notices and bundled license texts.

Pull requests remain required for main. Documentation and `.gitignore` changes get lightweight checks; changes to app code, tests, build resources or development tooling run the full verification suites.
