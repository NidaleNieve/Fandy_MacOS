# Fandy 0.3.0 build 23

System+ and Cool Chassis factory fan response is 20%. Existing saved tuning is preserved; Reset restores the new default. Version metadata agrees across app, helper and diagnostics.

The distribution script reuses the saved FandyNotary profile by default, checks credentials before signing, and never resets them. Existing private signing Team configuration is preserved. Default Keychain credential validation succeeded without a new password. An explicit login-Keychain lookup failed despite a successful default lookup; releases therefore preserve the default search behavior.

## Verification

New release-version, credential-reuse and ruleset tests failed against the previous implementation before correction. Final verification: 464 Swift tests (72 hardware, 233 core, 159 application), 58 Python tool tests, and signed Release compilation pass. Red and green logs are retained in ignored build output.

Two existing fixtures needed to express their original contracts explicitly after the factory response changed: idle reacquisition timing uses a Fast fixture; legacy comfort migration preserves the stored response instead of equating the whole profile with the new factory response. Production migration is unchanged. The quick factory-default edit was exempted from tests-first by the user's explicit instruction.

## Main protection

[Protect main](https://github.com/NidaleNieve/Fandy_MacOS/rules/24546308) is active and independently read back from GitHub. Pull requests, resolved conversations and four GitHub Actions checks are required: tests, sanitizers, native-release (macos-15), native-release (macos-latest). Main deletion and force pushes are blocked. No bypass actors are configured. Another person's approval is optional so the repository owner can merge their own passing PRs. The reproducible policy is in .github/main-ruleset.json.

Public release and updater publication remain held for user testing. No hardware command sequence changed; no new physical compatibility claim is made. Existing M2 official-signature acceptance and inaccessible-Mac runtime testing remain separate follow-ups.

## Local artifact

The final 0.3.0 build 23 app and DMG are Developer ID signed, notarized and stapled. Final mounted app/helper identity, hardened runtime, Gatekeeper app/image assessment, payload privacy and image integrity checks pass. The first DMG upload failed before a submission record existed; credentials remained valid and one retry completed successfully. No credentials were recreated.

SHA-256: `c5ef96ae9ff13f99db1fc89813e520a2133c02feb95acf741e9112736a670aac`. Artifact and verification report remain in ignored `build/Distribution-0.3.0`. Public release and updater feed are unchanged.
