# Temporary fan speed — 0.3.2 build 25

Choose **Custom Fan Speed** in the menu, move the 0–100% slider, choose a duration, and click **Activate**. Presets span five minutes to 24 hours; **Other…** accepts hours and minutes up to 31 days. Drafting a speed does not issue commands. The existing **Activate for/until** controls can change the timer, select an end time or application condition, or pin the selection with **Until Changed**.

On expiry or cancellation, the applicable schedule resumes; otherwise Fandy returns to the remembered ordinary profile. Manual selection of a saved profile replaces the temporary setting. Quit releases control and discards it. A valid selection may resume after verified wake, but sleeping never extends its deadline. **Settings → Menu Bar Menu → Show custom fan speed** hides the submenu without cancelling an active timer.

Percentages use each fan’s independently reported range: 0% is its minimum supported RPM, 100% its maximum. This is not a stopped-fan command or a promise of exact observed RPM. The normal response governor applies to changes. Required-chip validation, thermal-pressure handback, ownership checks, authenticated commands and watchdog recovery remain in force.

The runtime definition cannot enter saved profiles, the startup default, exports or imported hardware authority. Editing or undoing saved profile changes does not displace it. No fan-interface changes or new XPC methods were needed.

## Verification

Tests were written before implementation. The initial run failed because the temporary-speed APIs and visibility preference did not exist. The independent version acceptance test failed on 0.3.1/build 24. Further edit/undo regressions failed because collection replacement treated the temporary selection as a deleted profile; the minimal correction preserves runtime selection during unrelated edits.

The final focused run passes all nine selected tests (seven app behaviors, preference interchange and version identity). The complete suites pass **488 Swift tests** (72 hardware, 241 core, 175 app) and **58 tool tests**, with one job and no parallel test execution. Tests cover invalid and nonfinite input, 0/100% endpoints, expiry, scheduling precedence, re-timing, rapid replacement, hiding, profile edits/undo, archive exclusion, startup, eligibility, sensor failure and mock sleep/wake.

The nine focused tests also pass under Address Sanitizer. The signed, one-job Release compilation passed.

This delivery is local; GitHub release and updater publication remain unchanged. No physical fan experiment or installed-app/helper replacement was performed for this feature. UI checks use native menu construction, accessibility identifiers, model assertions and compilation.
