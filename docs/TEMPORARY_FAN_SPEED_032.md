# Temporary fan speed — 0.3.2 build 28

Choose **Custom Fan Speed** in the menu and move the 0–100% slider to activate it. Changes apply through the normal controller without a confirmation button. Opening the submenu does not activate cooling. The native **For …** submenu offers five minutes to 24 hours; **Other…** accepts hours and minutes up to 31 days. The last valid duration is remembered across menu reopening and app restarts. This stores the chosen duration, not the remaining countdown, and never restores a temporary manual selection at startup. Slider edits preserve the original timer and lease. Only a completed duration edit restarts the timer; unfinished fields preserve the active selection. Native slider tracking continues until mouse-up even outside the menu, and the slider has no tick marks. The existing **Activate for/until** controls can change the timer, select an end time or application condition, or pin the selection with **Until Changed**.

On expiry or cancellation, the applicable schedule resumes; otherwise Fandy returns to the remembered ordinary profile. Manual selection of a saved profile replaces the temporary setting. Quit releases control and discards it. A valid selection may resume after verified wake, but sleeping never extends its deadline. **Settings → Menu Bar Menu → Show custom fan speed** hides the submenu without cancelling an active timer.

Percentages use each fan’s independently reported range: 0% is its minimum supported RPM, 100% its maximum. This is not a stopped-fan command or a promise of exact observed RPM. The normal response governor applies to changes. Required-chip validation, thermal-pressure handback, ownership checks, authenticated commands and watchdog recovery remain in force.

The runtime definition cannot enter saved profiles, the startup default, exports or imported hardware authority. Editing or undoing saved profile changes does not displace it. No fan-interface changes or new XPC methods were needed.

**Settings → Menu Bar Menu → Show activate for/until** controls timing-submenu visibility. Each profile also has **Show in menu bar**, including System and Max. These settings default on. Hiding a profile does not deactivate it or disable its automation/shortcuts. Visibility survives persistence, duplication, undo and configuration/profile interchange; protected cooling definitions remain immutable.

## Build 28 timer correction

The build 27 popup action tests missed actual popup opening inside a tracked menu. A regression against that build failed because Custom Fan Speed had no ordinary native **For …** submenu. The correction replaces the embedded popup with standard menu items and action dispatch. A second acceptance run failed on the absent duration-persistence APIs before implementation.

The complete suites pass **504 Swift tests** (72 hardware, 247 core, 185 app) and **58 tool tests** with limited concurrency. New regressions exercise native submenu actions, remembered presets and custom durations, restart/configuration round trips, invalid values, unchanged deadlines on reopening and slider edits, and retiming without replacing the active lease. All seven focused regressions pass under Address Sanitizer, and the signed arm64 Release build passes. Automated native-menu actions do not constitute physical click-to-open acceptance; that remains for local user testing. No manual fan request or stress workload was used. Build 28 app and final DMG are Developer ID signed, notarized and stapled. Independent Gatekeeper, mounted payload and integrity verification pass. Local installation preserved the configuration byte-for-byte; the registered helper reports build 28, no fault and automatic ownership on both fans. Fandy is left closed for local menu acceptance. GitHub release and updater remain unchanged.

## Build 27 verification

Tests preceded implementation. Initial compilation rejected the missing visibility/control APIs. The build-identity acceptance test then failed against build 26. A further behavioral regression showed that opening custom-duration fields renewed the timer and invalid fields prevented speed edits; all four assertions now pass without weakening them. One intermediate test fixture lacked an explicit undo group after disabling event grouping; its setup was corrected.

The full suites pass **500 Swift tests** (72 hardware, 245 core, 183 app) and **58 tool tests**, with limited concurrency. All nine new regressions pass under Address Sanitizer. Signed arm64 Release compilation and strict app/helper signature verification pass. Mouse-tracking policy is checked through an injected cell; no visual or physical fan testing was performed. Manual confirmation of the native menu interaction remains part of local user acceptance.

Build 27 is now Developer ID signed, notarized and stapled, including the final DMG. The existing `FandyNotary` credential was accessible on the next attempt; no credentials were recreated. Gatekeeper, strict app/helper signatures, mounted DMG contents and checksum verification pass. Local installation used verified handback, normal quit, helper unregister/register and a preserved rollback copy. The installed build 27 helper is enabled and healthy, both fans are verified automatic, and the user profile/settings file is byte-for-byte unchanged. Fandy is left closed for manual local acceptance. GitHub release and updater publication remain unchanged.

## Original build 25 verification

Tests were written before implementation. The initial run failed because the temporary-speed APIs and visibility preference did not exist. The independent version acceptance test failed on 0.3.1/build 24. Further edit/undo regressions failed because collection replacement treated the temporary selection as a deleted profile; the minimal correction preserves runtime selection during unrelated edits.

The final focused run passes all nine selected tests (seven app behaviors, preference interchange and version identity). The complete suites pass **488 Swift tests** (72 hardware, 241 core, 175 app) and **58 tool tests**, with one job and no parallel test execution. Tests cover invalid and nonfinite input, 0/100% endpoints, expiry, scheduling precedence, re-timing, rapid replacement, hiding, profile edits/undo, archive exclusion, startup, eligibility, sensor failure and mock sleep/wake.

The nine focused tests also pass under Address Sanitizer. The signed, one-job Release compilation passed. The local DMG is Developer ID signed, notarized and stapled; app/image Gatekeeper assessment, mounted payload, privacy and integrity checks passed.

This delivery is local; GitHub release and updater publication remain unchanged. No physical fan experiment or installed-app/helper replacement was performed for this feature. UI checks use native menu construction, accessibility identifiers, model assertions and compilation.
