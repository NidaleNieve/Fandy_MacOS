# Multiple application conditions — 0.2.4 build 22

Each profile keeps its own application list under When Activated. Installed applications support multiple selection; the searchable running-program picker can include helper processes such as Java. Launch triggers match any selected application. Optional closing behavior keeps the profile active while any selected application or matching process instance remains running. Programs can be added or removed individually without losing the other selections.

Manual activation remains possible before the programs open. That watch waits for a selected program to run, then ends when all selected programs close. Selecting a menu duration, Until Changed or an exact menu process watch replaces the profile's group watch. Manual overrides, schedule priority, startup/wake baselines and safe System restoration remain unchanged. Editing a rule baselines already-running programs rather than treating them as new launches. A profile's active watch captures its admitted selection; subsequent rule edits apply on the next activation.

Legacy one-application rules migrate to a one-entry list. Storage, portable configurations, individual profile export/import, duplication and undo preserve the full list. Entries store application bundle IDs or process executable names, never PIDs, command arguments, personal paths or fan-control authority. Runtime process observations still verify PID and start time. Process rules match every instance of that executable name; they cannot distinguish separate games that share the same Java executable. Select their distinct application bundles when available.

The automatic-update frequency picker now contains Daily, Weekly and Monthly. Automatic Updates is the single enable/disable control. Legacy Never configurations migrate to automatic updates disabled with Weekly selected, so migration does not silently enable checks.

## Tests-first verification

Before production changes, seven new application-condition tests and one update-frequency test failed against the old implementation for dropped list entries, missed secondary triggers, early closure, invalid entries, legacy encoding and the redundant Never option. A later existing short-lived-app regression and a new helper-process baseline test failed before their corrections. Build-number acceptance failed at 21 before incrementing to 22. Fixture-only initialization/undo-group errors were corrected separately; intended behavioral assertions were retained.

The final complete suite passes 463 Swift tests (72 hardware, 232 core, 159 app) and 52 tool tests. App tests use real bounded child processes with a simulated fan backend, including either-launch/all-close, several instances of the same process, observed exit between ticks, waiting manual activation, startup/wake suppression, per-profile storage, undo and timer replacement. No physical fan transactions were modified or new thermal workload generated. Release and local package results are recorded in the delivery checkpoint.

The single-job signed arm64 Release build passes. The local DMG is Developer ID-signed, notarized and stapled; app/helper signatures, hardened runtime, tickets, Gatekeeper, mounted payload, image integrity and privacy checks pass. Public release and updater-feed publication remain held for user acceptance.
