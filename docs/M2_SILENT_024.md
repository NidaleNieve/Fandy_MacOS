# Fandy 0.2.4 build 21 — M2 integration and Silent

## Changes and provenance

PR [#1](https://github.com/NidaleNieve/Fandy_MacOS/pull/1), original commit `19b6a32482a408e1138c7f387ab42349242cad97`, is retained as a merge parent with the contributor's original authorship. The integration preserves build 20's curve-first control and per-fan mode/acknowledgement/target ordering. Accepted reference mode commands are polled every 50 ms within the original seven-second admission deadline, never rewritten. Bounds, metadata, ownership, cancellation and required readings remain checked during waiting. A bounds change at acknowledgement aborts before targeting. Automatic release waits at most one second per commanded reference fan, attempts every fan independently and retains global release plus final mode readback. The local M5 recipe stays unchanged.

Silent replaces the built-in School display name. The `school` ID is intentionally retained. Storage and portable/scheduled imports rename only the legacy built-in name; cooling edits, custom names, schedules, activation defaults and saved selections survive. Schedule text accepts the old School alias only when an exact-name profile does not take precedence. New exports use the visible name. Historical measurement reports retain School with a rename note.

`AGENTS.md` makes tests-first development a repository-wide requirement. No helper permissions, XPC methods, hardware keys or imported control authority were added.

## Verification

The tests-first commit precedes production integration. Initial behavioral regressions failed for delayed admission, deadline handling, display/export name, storage/import migration and legacy schedule alias. The new release/removal contracts initially failed compilation because their implementation was absent. A subsequent acknowledgement/bounds race test failed before its correction. Private logs retain these red runs; no raw hardware data is published.

The complete suite passes 454 Swift tests (72 hardware, 228 core, 154 app) and 52 tool tests. Focused AddressSanitizer passes 40 tests. A single-job signed Release build passes, with app/helper version 0.2.4 / 21, arm64 deployment and independently verified package/signatures. Existing label/build assertions were updated to the requested Silent/build-21 contract; undo, generation and diagnostic assertions remain intact.

Focused ThreadSanitizer passes four cancellation/admission/restoration tests. GitHub runs 37383722556 and 37385352256 pass tests, sanitizers and native Release compilation on macos-15 and macos-latest. The latter verifies the final integration after preserving a README-only upstream commit; that commit changes no production or test code.

The installed M5 Pro passed three fixed modest System–Silent transitions. Mode-to-target gaps ranged 1.186–1.624 ms; independent 20-Hz observations met the existing overshoot bound. A five-minute ordinary-use run passed with 252 samples spanning 299.55 seconds under nominal thermal pressure, demand 2.76–17.40% and RPM 0–3283. No automatic-at-idle interval occurred during that warm workload, so this run does not independently prove idle release/re-entry; the existing tests/evidence remain. No synthetic stress was generated.

Normal quit, disconnect and heartbeat recovery passed with independent automatic-mode observations at approximately 0.031/0.267/10.220 seconds. Final status reported helper build 21 ready on attempt one, approved registration and both fans in mode 0 at 0 RPM.

Xcode's initial Release used Apple Development signing, whereas the existing service was Developer ID. That local installation attempt failed a launch constraint and did not admit control. Matching Developer ID staging corrected the signature class; subsequent startup and all hardware checks passed without changing permission. Packaging uses the established distribution-signing workflow. Final notarization/merge status is recorded below; no release or update feed is published.

## Compatibility boundaries

The contributor reports Mac14,9 / M2 Pro direct-interface profile and recovery measurements using separate signed identities: quit ~0.35 s, disconnect ~0.54 s, heartbeat ~10.04 s. Those are contributor observations, not Fandy's local physical tests or official-identity startup acceptance. M2 Ftst, active sleep/wake and helper termination were not retested. M1/M3/M4 and other M5 configurations have synthetic timing coverage and retain reference-supported status. The M5-only `locallyTested` adapter flag is unchanged. A dead or blocked helper cannot execute its watchdog.

## Merge and local delivery

PR #1 is merged through `cd8ff0a`, retaining the contributor's original commit and authorship. The final CI-verified integration `a9bffba` is on main, including the newer upstream README edit. New corrections use the repository owner's GitHub identity.

The local 0.2.4 build 21 arm64 DMG is Developer ID-signed, notarized and stapled. App/helper identities, hardened runtime, app/image tickets, Gatekeeper assessment, mounted payload, image integrity and payload privacy checks pass. It contains only Fandy and the Applications shortcut. Checksum and verification metadata remain local; no release asset or updater feed was published.

The installed app was replaced with the notarized DMG payload after verified automatic handback, helper unregistration and job removal. Installed ticket, Gatekeeper and strict signature checks pass; re-registration reports enabled, with both fans independently observed in automatic mode at 0 RPM. The GUI is closed so reopening can follow the user's preserved configuration. A transient Apple ticket-validation DNS failure stopped an earlier install attempt before replacement; the subsequent validation and installation passed.

User profiles and application identity remain unchanged. Public release and update-feed publication wait for user acceptance. Official-signature installation/startup on the contributor's M2 remains pending, as do inaccessible-hardware physical checks and the previously noted sleep/wake and helper-death limitations.
