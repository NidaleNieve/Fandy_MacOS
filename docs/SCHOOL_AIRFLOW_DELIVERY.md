# School and fan-percentage update — 2026-10-05

Version 0.2.0, build 9.

## Changes

Fan bars and percentage readouts now use the same minimum-to-maximum range as curves and minimum airflow: `(observedRPM - minimumRPM) / (maximumRPM - minimumRPM)`, clamped to 0–100. Actual RPM remains displayed. Previously the readout divided by maximum RPM, so a correct 28% target appeared around 49%, and 50% appeared around 65%, with the locally reported limits. This change does not lower hardware limits or change the production RPM mapping. A curve/floor is a minimum demand, not a cap; another input or the chip guard may require more cooling. Automatic readings below the manual minimum, including stopped fans, display 0%.

School's factory revision 2 uses the supplied quieter chip curve: 45°C/0%, 56.9°C/14%, 66.1°C/35%, 73.8°C/47%, 79.3°C/50%, 86.9°C/52%. Comfort curves match the supplied definition; minimum airflow remains 0 and Apple automatic at idle remains enabled. The immutable chip guard still wins under higher chip temperatures. Only an unchanged revision-1 factory profile is migrated; edits, renamed profiles, schedules and activation conditions are preserved. Reset to Default applies the new definition to an edited School profile.

Profile, configuration and diagnostic exports all initialize their native save panel in Downloads and retain their appropriate filenames.

## Verification

381 Swift tests pass (48 hardware, 198 core, 135 app) with one job and no parallel execution, plus 48 tool tests. Coverage includes independent fan-range round trips, 28%/50% floor targets, stopped/invalid observations, the exact School curves, chip escalation, safe factory migration, preservation of edits/automation, and Downloads panels. An obsolete menu test was corrected to assert the shipped full-title cancellation wrapping rather than the superseded truncated native label; other action rows remain native and menu width stays bounded.

The signed arm64 Release build passes. Verification uses an isolated source snapshot because a separate review task is modifying the shared helper. Its unfinished helper and persistence changes are excluded from this artifact. The only physical observation during development was a read-only fan snapshot; no fan experiments were performed. Raw observations and the supplied profile's schedules and identifiers are excluded from Git.

The build-9 DMG is Developer ID-signed, notarized and stapled. App/image Gatekeeper assessments, tickets, signatures, mounted contents, private-data exclusion and image integrity pass the distribution pipeline. Its SHA-256 is `fd67161651be08f111d1e0bccd0f61ae0c88cd2bffa94c32d48b09f1f7dd8051`. Distribution output is kept under ignored `build/Distribution-School-0.2.0-build9`. The existing public GitHub build 8 is separate until intentionally updated. Installed user configuration is not replaced by development or packaging.
