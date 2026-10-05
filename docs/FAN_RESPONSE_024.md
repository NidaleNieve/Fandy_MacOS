> Naming note: School was renamed Silent in 0.2.4 build 21. Historical observations below retain the name used during measurement.

# Fandy 0.2.4 — build 20

Local test release; GitHub publication and update-feed changes wait for user acceptance. Build 19's independent fan guard is superseded.

## Delivered behavior

Nominal/fair-pressure demand follows enabled curves, minimum airflow and an optional target. There is no independent 75°C/85°C escalation in the GUI engine, helper validation, watchdog or reference adapter. Complete required-chip readings still cannot be deselected. Serious/critical/unknown pressure, sensor failure, metadata failure or ownership loss hand back directly to macOS, without a preceding maximum command. A profile's highest possible configured demand bounds inherited governor output; fresh actual RPM seeds entry and idle reacquisition.

Fan response shows 0–100%, a short explanation, smoothing seconds and percentage points/s. Quiet retains three-second time-weighted averaging/two-point rises; Fast retains zero-second averaging/ten-point rises. Apple auto at idle explains the unchanged 15-second release and sustained 5%/three-second resume conditions. Curves, schedules, activation defaults and saved user configuration are preserved. Legacy decoding, undo, duplication and import/export remain covered.

The authenticated helper listener now precedes hardware bootstrap. Failed initialization/restoration remains observable through structured status and rejects leases. Transient SMC failures receive only the fixed one-/three-second retries; unknown metadata/authentication do not. Approved-but-unavailable helpers expose Retry/Export Diagnostics instead of an approval loop. Only native requiresApproval opens setup. Already-automatic reference modes avoid a redundant protected write, with global release and final readback still required.

## Software verification

437 Swift tests pass: 61 hardware, 224 core, 152 app. All 52 tool tests pass. A single-job signed arm64 Release build passes with app/helper identity 0.2.4 / 20. Tests cover capped demand at 75/85/105°C nominal/fair pressure; severe-pressure handback; full sensor loss; ordinary smoothing; fresh/stale entry and inherited ceilings; complete metadata preflight; mixed-mode reference batches; cancellation; partial restoration; protected automatic modes; approved failed/initializing/restoring backends; bounded retries; and existing authentication/persistence/scheduling/lifecycle behavior.

## Physical transition investigation

The initial bounded run passed its first modest entry (mode-to-target approximately 1.3 ms), but failed the second entry's acknowledgement and restored both fans. That result is retained as failed evidence. Code inspection found that full fan acknowledgement still delayed the second admission; it was moved after every fan had received its target. This keeps each mode/narrow-mode-read/target sequence adjacent, avoids repeated enumeration while only one fan is manual, and introduces no alternate keys, target clearing or preloading.

The corrected run passed all three fixed modest System–School transitions. Recorded mode-to-target gaps were 1.229–1.369 ms. Independent 20-Hz sampling detected no RPM overshoot beyond its conservative comparison bound. This is bounded evidence, not proof that a sub-50-ms physical event cannot occur. The diagnostic uses a temporary School floor of 5% to ensure admission, restores the unmodified factory profile afterward, and does not write user configuration.

## Local delivery and remaining acceptance

The Developer ID signed build is installed after verified normal-quit handback, ServiceManagement unregister and old-job absence. Registration stayed enabled; startup reported ready on attempt one and independent fan modes were both 0. The notarization credential profile `FandyNotary` is currently absent from Keychain; a private re-save was requested. No unnotarized build is published.

The five-minute factory-School run passed with 267 independent samples spanning 299.84 seconds (median interval 1.109 seconds). Natural chip-envelope readings ranged 30.23–71.06°C under nominal pressure. Governed demand ranged 0–15.58%; the largest adjacent change was 2.744 points over an elapsed interval, consistent with the Quiet rise limit. Fans ranged 0–3183 RPM. There were 159 automatic-at-idle samples and successful release/re-entry, followed by verified System and normal termination. This trace demonstrates bounded stable ordinary-use behavior; it is not a controlled before/after acoustic comparison or a high-temperature stress test.

Additional bounded production checks passed: normal-quit handback observed in 0.016 seconds, disconnect in 0.271 seconds and heartbeat expiry in 9.994 seconds. These use a modest factory Cool Chassis lease through the same production writer. Controller SIGKILL also restored both manual fans within 0.146 seconds; RPM coasted down after ownership had already returned. Eleven signed protocol checks passed, including malformed/oversized input, unknown roles, overflow, wrong version, caller authority, forged targets and wrong helper identity. Final status showed enabled registration, helper build 20 ready on attempt one, no fault and both modes/RPM 0.

One native registration attempt immediately after the final replacement returned Operation not permitted while background approval remained allowed. A single subsequent native registration succeeded without a permission change. This is retained as a transient service-registration observation, not evidence that the friend’s M2 cause is known. Actual active sleep/wake and high-load throttling are not exercised. No synthetic stress, Max test, power change or guessed M2 recipe is used. Friend M2 startup acceptance remains pending diagnostics or their corrected-build test. A dead/blocked helper cannot execute its watchdog. Fandy cannot command thermal throttling or guarantee fanless behavior, and macOS-controlled fan changes remain outside the profile ceiling.
