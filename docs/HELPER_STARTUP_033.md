# Helper startup — 0.3.3 build 30 local candidate

The app registers its correctly signed embedded helper independently of GUI-side hardware access. App and helper seals, fixed identifiers, matching signing teams and matching development/distribution classes are checked before registration. Native approval, authenticated service availability, monitoring and profile eligibility remain separate. Only `requiresApproval` opens the background-activity guide.

Registration, legacy migration, removal and replacement use a serialized lifecycle coordinator. Replacement preserves handback from a reachable controller and waits for the native unregister status transition. A missing-service XPC result is confirmed twice more before the single automatic rebind; timeouts, authentication rejection and reported startup progress never trigger that rebind. An explicit Retry remains available. Expected helper build verification detects stale replacement without trusting registration status as proof of launch.

Startup is listener → shared SMC session → fan discovery → automatic recovery → sensor discovery → monitoring/control readiness. Successful recovery is adopted by the ready coordinator without a second physical transaction. Hardware initialization failure does not remove the authenticated status endpoint. Health replies use a short-lock immutable snapshot and reserved request capacity; they never touch hardware or extend a lease. Old snapshots cannot prove fresh automatic ownership. Hardware operations remain serialized and cancellation-fenced.

The production SMC packet decoder is injectable. Temperature metadata is reused after successful usable values and invalidated on failure; mode/target metadata is still refreshed for transactions. Selected sensor membership remains fixed within a resolved backend. Initial transient open/discovery failures retry at the existing one/three-second offsets, at most three attempts. Unsupported metadata does not retry automatically. A failed transient startup may try again after wake; a ready backend or active lease never gets rediscovered by a delayed retry. Wake clears acquisition/governor state through the existing lifecycle; an active lease never changes sensor membership.

Restoration attempts every fan and global release independently. Intermediate manual readback before Ftst clearing is retained as evidence, not a premature failure. Final reference-mode polling is bounded to one second per fan. Physical write failure, unknown mode or failed global clearing still makes restoration unverified. Already-automatic observations remain distinct from release of manual control. No target clearing, arbitrary SMC commands or thermal-policy changes were added.

Export Diagnostics works without a reachable helper. It collects the build/model/chip, native registration, structured failure domain/code/operation, startup phase, readable fan metadata even when its interface cannot write, selected groups, signature-validity and identity-match booleans. A fixed read-only launchctl query supplies only state, PID and last exit code. Raw output, paths, signing names, serial numbers, schedules and profile names are excluded. Collection runs away from the main actor and the query is bounded to two seconds.

## Tests-first evidence

Local ignored logs record the initial missing-boundary API failures, final-ownership failure before the release correction, missing lifecycle/signature APIs, missing bootstrap/diagnostic injection, narrowed-envelope acceptance, hidden target failures, invalid-value metadata caching and lost firmware errors. The matching acceptance tests retain their original expectations. Compiler mistakes during integration are not counted as regression evidence.

Production-path fixtures are synthetic/reference-derived, not measurements. All 27 compiled notebooks exercise actual packet decoding, fan discovery, selected sensor resolution and sampling. Actual helper bootstrap tests cover already-automatic reference startup; the local direct recipe is denied physical writes in the unprivileged test process. The actual status dispatcher responds during an intentionally blocked hardware queue.

## Remaining acceptance

- Export the failing M2's report before another reinstall; test the official notarized identity.
- Clean macOS 15/later VM installation, approval, upgrade, reboot and damaged-installation sessions require provisioned guests. No suitable local VM app or restore image was found.
- Verify the candidate's installed M5 status/ownership and bounded quiet transitions before public release.
- On M2, verify monitoring, a five-second modest upward trial, independent handback, quit/disconnect/heartbeat and supervised restart/sleep/wake.

The exact M2 official failure is still unknown. Synthetic coverage does not certify inaccessible hardware. A dead helper or blocked kernel call cannot run its watchdog; responsive cached status exposes the last completed work but cannot interrupt that call. Public release and updater feed remain held for acceptance.

## Local verification state

The final complete suite passed 535 Swift tests and 59 Python tool tests. Full AddressSanitizer passed 529 tests before the final sensor-menu and stalled-status additions; focused AddressSanitizer covered the changed sensor-menu path and focused ThreadSanitizer covered the status/lifecycle changes. The additional transient-wake regression and varied Base/Pro/Max packet scenarios are included in the final required CI run. Signed arm64 Release compilation succeeded with macOS 15 deployment.

Initial notarization preflight reported the existing FandyNotary item missing from both default and login Keychain lookups. After resumption its default lookup succeeded. No credentials were recreated and no unnotarized DMG was published. Final packaging and physical acceptance are recorded below when completed; an earlier build must not be presented as the candidate.
