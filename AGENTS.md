# Fandy development instructions

## Tests first

For every feature, fix, or behavior change, write regression or acceptance tests
before modifying production code. Run them against the existing implementation
and confirm they fail for the intended reason. Implement the smallest correction,
then run the new tests and relevant existing suites. Record the failing and passing
verification results. Never weaken assertions simply to accommodate implementation
behavior. For contributions that already contain code, add and run missing
regressions before adapting or correcting that contribution.

Use meaningful behavior tests rather than implementation mirrors. Documentation
and purely descriptive changes use relevant validation checks where applicable.

## Hardware and release

Keep fan transactions bounded, authenticated and independently verified. Unknown
ownership, failed required readings or invalid metadata returns control to macOS.
Tests must use injected transports before physical writes. Finish live sessions
in verified System mode; never claim synthetic fixtures prove physical compatibility.

Preserve user configuration and stable profile identifiers during migrations.
Author new commits using the repository owner's configured Git identity; preserve
original contributor authorship. Keep credentials, signing configuration and raw
measurements out of Git. Notarize verified builds before public distribution.

## Protected main

Develop on a branch and merge through a pull request. Main requires resolved review
conversations and the tests, sanitizers, native-release (macos-15), and
native-release (macos-latest) GitHub Actions checks. Do not bypass the ruleset or
force-push main. The reviewed configuration is `.github/main-ruleset.json`.

Reuse the saved `FandyNotary` Keychain profile and existing ignored signing
configuration. Never recreate credentials merely because a lookup fails.
