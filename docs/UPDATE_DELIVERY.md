# Fandy 0.2.2 update integration

Version **0.2.2**, internal build **12**, adds pinned Sparkle 2.10.0 updates. Automatic mode is enabled by default: weekly checks, verified download, installation on quit, and Sparkle’s two-week impatient reminder. With automatic mode off, Settings provides Check for Updates and Never/Daily/Weekly/Monthly frequencies. Automatic mode disables those two controls. Preferences round-trip through configuration exports; imports cannot change the feed, signing key or hardware authority.

## Verification

- 401 Swift tests: 53 hardware, 208 core, 140 application tests.
- 51 Python tool tests and successful signed arm64 Release compilation.
- A separate signed native fixture fetched its local feed and archive, staged the update, and replaced build 11 with build 12 on normal quit. It contains no fan helper and uses a separate defaults identity.
- The same real Sparkle path rejected a modified archive with signature error 4005; the original installation remained unchanged.
- Deterministic clock tests cover weekly intervals and the two-week reminder boundary. The native two-week elapsed interval was not waited out.
- Tests require a release acknowledgement and verified per-fan restoration report before update preparation succeeds, reject an unavailable helper during custom control, coalesce duplicate preparation requests, and allow retry after failure.
- App and DMG are Developer ID signed, notarized and stapled. Gatekeeper, mounted payload, matching app/helper identity, image integrity and privacy checks pass. Verification reports/checksums remain local; only the DMG is a release attachment.

## Lifecycle and limitations

The GUI stops controller work, invalidates stale replies, restores macOS control independently of temperatures, saves configuration and unregisters the old helper before consenting to normal update installation. Startup detects an old helper build, releases it, and attempts one bounded registration refresh before allowing profiles. New native Background App Activity approval may be required.

Normal update preparation is covered with injected clients. The native installer fixture exercises actual replacement without physical fan ownership; it is not a live fan-helper upgrade recovery matrix. A forced process kill bypasses normal quit preparation, and a dead or blocked helper cannot run its watchdog. Existing watchdog/startup recovery remains essential.

No running Fandy installation, personal configuration or live helper was replaced during these release checks. The original fan-control algorithms and qualified hardware registry remain unchanged.

## Future releases

Retain the local updater private key and increment both Info.plist and FandyBuild. Test, sign, notarize and staple before signing the final archive and publishing a release/feed. See [distribution instructions](DISTRIBUTION.md). Use the repository owner’s configured GitHub author identity for future commits.
