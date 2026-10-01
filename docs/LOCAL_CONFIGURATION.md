# Local configuration and public-repository privacy

The public project contains no developer Team ID or personal provisioning profile. To sign locally, create ignored `Config/Signing.local.xcconfig` and set `DEVELOPMENT_TEAM` to your own Team ID. Public defaults use Automatic signing and Apple Development. App/helper identifiers remain `is.dsr.fandy` and `is.dsr.fandy.fan-helper`.

The generator migrates Xcode signing selections into ignored per-configuration files under `Config/Signing/`. Existing selections remain effective, including conditional settings. Public wrappers include these files optionally. Run `Scripts/generate-project.py` before committing after changing signing in Xcode; the privacy check rejects inline developer identities.

Ignored data includes build products/caches, Xcode user state, raw CSV/JSONL/log files, diagnostics, credentials/certificates, local signing and operator-specific evidence reports. Use `docs/local/` or `private/` for additional notes. Existing evidence remains locally available and is not deleted by publication. Analysis commands require explicit local paths; no user's document path is built into source.

Enable the staged-content check:

```sh
git config --local core.hooksPath .githooks
python3 Scripts/check-public-content.py --staged
```

The hook checks the complete Git index for private paths, local account/signing identifiers, home-directory paths, emails outside required third-party notices, common credential formats and binary/oversized artifacts. It reports categories and paths without sensitive matches. These checks supplement manual review; they cannot guarantee detection of every secret or personal detail.

Use a nonpersonal commit author/email if desired. This project does not change global Git identity or credentials. Required third-party copyright/license attribution is retained; those notices are not operator data.
