# Helper startup — 0.3.3 integrated release candidate

The app registers its correctly signed embedded helper independently of GUI-side hardware access. App and helper seals, fixed identifiers, matching signing teams and matching development/distribution classes are checked before registration. Native approval, authenticated service availability, monitoring and profile eligibility remain separate. Only `requiresApproval` opens the background-activity guide.

Registration, legacy migration, removal and replacement use a serialized lifecycle coordinator. Replacement preserves handback from a reachable controller and waits for the native unregister status transition. A missing-service XPC result is confirmed twice more before the single automatic rebind; timeouts, authentication rejection and reported startup progress never trigger that rebind. An explicit Retry remains available. Expected helper build verification detects stale replacement without trusting registration status as proof of launch.

Startup is listener → shared SMC session → fan discovery → automatic recovery → sensor discovery → monitoring/control readiness. The current daemon uses `is.dsr.fandy.fan-control-v2` with a fixed executable under `/Applications/Fandy.app`. Both signing classes must run from that location. The migration removes the two predecessor registrations only after verified handback from a reachable helper; confirmed service absence permits replacement startup to verify restoration. Timeouts, failed handback and failed removal block migration. Authentication errors also block removal unless fresh independent SMC observations prove complete automatic ownership and a cleared Ftst flag. This exception retires only the predecessor registration; it never accepts an unauthenticated connection or grants a control lease. The existing XPC identity remains unchanged.

Successful recovery is adopted by the ready coordinator without a second physical transaction. Hardware initialization failure does not remove the authenticated status endpoint. Health replies use a short-lock immutable snapshot and reserved request capacity; they never touch hardware or extend a lease. Old snapshots cannot prove fresh automatic ownership. Hardware operations remain serialized and cancellation-fenced.

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

The integrated complete suite passed 545 Swift tests and 61 Python tool tests. Full AddressSanitizer passed 529 tests before the final sensor-menu and stalled-status additions; focused AddressSanitizer covered the changed sensor-menu path and focused ThreadSanitizer covered the status/lifecycle changes. The additional transient-wake regression and varied Base/Pro/Max packet scenarios are included in the final required CI run. Signed arm64 Release compilation succeeded with macOS 15 deployment.

Initial notarization preflight reported the existing FandyNotary item missing from both default and login Keychain lookups. After resumption its default lookup succeeded. No credentials were recreated and no unnotarized DMG was published. Final packaging and physical acceptance are recorded below when completed; an earlier build must not be presented as the candidate.


Build 30 was notarized and retained separately. Build 31 also shares authenticated readiness preparation across profile, recovery, sleep and maximum diagnostics. Live recovery diagnostics use a temporary chip-checked definition capped at 10%, request an upward margin of at least 200 RPM within each fan's bounds, and skip when that quiet margin is unavailable. They never alter stored user profiles. Maximum diagnostics remain implemented but are not run during quiet local acceptance.

## PR #6 review and integration

[PR #6](https://github.com/NidaleNieve/Fandy_MacOS/pull/6) adds a distinct diagnosis:
Background Task Management can lose the parent-container record and the job exits
with EX_CONFIG (78). Rebinding the old label can retain that failed BundleProgram
resolution. The fixed Program path and fresh label address this path; responsive
status and shared SMC discovery in this branch address separate startup failures.

All eleven contributed files were reviewed. The new plist, identity constants,
packaging checks, generated project, developer installation guidance and regression
coverage were incorporated. The old embedded HelperManager change was adapted into
the extracted serialized manager, retaining hardware-independent registration,
both app/helper signature checks, signing-class matching and typed connection errors.
The original contributor commit remains an ancestor of the integration.

Tests were written and run before adapting production code. Packaging rejected the
new valid fixed-path recipe, generated embedding omitted the new plist, and the
Swift suite lacked the migration API. After integration the focused ten regressions,
complete Swift suite and tool suite passed. Additional tests distinguish typed service
absence from authentication/timeout, preserve both predecessor labels and verify all
migration plists are embedded. Raw logs stay local and ignored.

The contributor reports locally signed M2 Pro startup and Max-to-System handback on
this fix. Their official Developer ID acceptance is still pending. The change does
not expand sensor authority or claim physical certification for other Macs.


Native manual replacement exposed a second issue: the previously running helper
could no longer satisfy XPC signing validation after its executable was replaced.
Simply restoring the old app files did not repair that running process. A regression
now requires independent current automatic ownership before retiring this specific
unreachable predecessor. Its read-only proof validates the compiled recipe, all mode
keys, cleared Ftst where applicable, one-second completed-acquisition window and
unchanged fan count. It rejects manual, stale, missing, contradictory and changing
observations without writes. Inspection runs outside the main actor. Sparkle already
unregisters the reachable helper after verified handback and before app replacement;
that path remains unchanged.


## Official local installation acceptance

The integrated Developer ID candidate was signed, notarized and installed as
0.3.3 build 31 to preserve an older internal version for updater testing. Native
migration recovered the observed stale-signature predecessor, removed both old
service records and started the fixed-path service. Authenticated build 31 status
reported ready on its first bootstrap attempt; both fans were independently observed
automatic. Configuration bytes were unchanged. No additional native approval was
required on the available M5.

Twenty read-only ordinary-use samples passed the existing performance thresholds:
sensor acquisition p95 36.0 ms, authenticated status p95 3.4 ms, monitoring tick p95
37.5 ms, profile evaluation p95 1.8 ms and main-actor dispatch p95 5.2 ms (400 dispatch
samples). Native negative protocol checks rejected malformed/oversized JSON, unknown
roles, overflow/wrong generations and versions, caller authority, forged targets,
obsolete qualification and wrong helper identity. Reconnection stayed healthy.

The quiet manual recovery trial was skipped because its upward-margin gate was
unavailable with stopped fans. This is not evidence of manual-release recovery on
this candidate. No Max, Gaming, stress workload or forced sleep was used. Final state
was verified System. Official M2 installation/control acceptance and clean VM runtime
sessions remain pending. Public build 32 retains the same functional changes and
uses 0.3.3 with a newer internal build so the locally installed 31 can test Sparkle.
