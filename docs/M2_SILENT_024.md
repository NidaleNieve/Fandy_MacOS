# Fandy 0.2.4 build 21 — M2 integration and Silent

## Changes and provenance

PR [#1](https://github.com/NidaleNieve/Fandy_MacOS/pull/1), original commit `19b6a32482a408e1138c7f387ab42349242cad97`, is retained as a merge parent with the contributor's original authorship. The integration preserves build 20's curve-first control and per-fan mode/acknowledgement/target ordering. Accepted reference mode commands are polled every 50 ms within the original seven-second admission deadline, never rewritten. Bounds, metadata, ownership, cancellation and required readings remain checked during waiting. A bounds change at acknowledgement aborts before targeting. Automatic release waits at most one second per commanded reference fan, attempts every fan independently and retains global release plus final mode readback. The local M5 recipe stays unchanged.

Silent replaces the built-in School display name. The `school` ID is intentionally retained. Storage and portable/scheduled imports rename only the legacy built-in name; cooling edits, custom names, schedules, activation defaults and saved selections survive. Schedule text accepts the old School alias only when an exact-name profile does not take precedence. New exports use the visible name. Historical measurement reports retain School with a rename note.

`AGENTS.md` makes tests-first development a repository-wide requirement. No helper permissions, XPC methods, hardware keys or imported control authority were added.

## Verification

The tests-first commit precedes production integration. Initial behavioral regressions failed for delayed admission, deadline handling, display/export name, storage/import migration and legacy schedule alias. The new release/removal contracts initially failed compilation because their implementation was absent. A subsequent acknowledgement/bounds race test failed before its correction. Private logs retain these red runs; no raw hardware data is published.

The complete suite passes 454 Swift tests (72 hardware, 228 core, 154 app) and 52 tool tests. Focused AddressSanitizer passes 40 tests. A single-job signed Release build passes, with app/helper version 0.2.4 / 21, arm64 deployment and independently verified package/signatures. Existing label/build assertions were updated to the requested Silent/build-21 contract; undo, generation and diagnostic assertions remain intact.

ThreadSanitizer, GitHub CI, installed hardware regression and final notarization results are recorded below when complete. Until then this is a local integration candidate, not a published release.

## Compatibility boundaries

The contributor reports Mac14,9 / M2 Pro direct-interface profile and recovery measurements using separate signed identities: quit ~0.35 s, disconnect ~0.54 s, heartbeat ~10.04 s. Those are contributor observations, not Fandy's local physical tests or official-identity startup acceptance. M2 Ftst, active sleep/wake and helper termination were not retested. M1/M3/M4 and other M5 configurations have synthetic timing coverage and retain reference-supported status. The M5-only `locallyTested` adapter flag is unchanged. A dead or blocked helper cannot execute its watchdog.

User profiles and application identity remain unchanged. Public release and update-feed publication wait for user acceptance.
