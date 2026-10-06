# Fandy 0.3.1 build 24 — response and system sleep

## Changes

Fan response now uses `15 × (1 − response)` seconds of time-weighted
averaging. Quiet is 15 seconds; the System+ and Cool Chassis 20% defaults are
12 seconds; Fast is unsmoothed. The existing upward rate, downward hold,
configured ceilings, hardware limits and thermal-pressure handback remain.
Saved profile curves, response values, idle choices and automation are preserved.

Actual system sleep restores macOS, pauses GUI monitoring/automation/periodic
updates and independently blocks helper leases. Verified wake resolves a valid
manual override, then the current schedule, then the previous ordinary profile.
Expired timers and closed application conditions do not restart. Faults or failed
wake checks retain macOS control. Display sleep alone deliberately does not
suspend control. Daily is the default update frequency; explicit weekly/monthly
choices and the Automatic Updates toggle remain intact.

Local surge records capture a commanded or observed increase of ten percentage
points within ten seconds, with 30 seconds of preceding context and a fixed
60-second follow-up. Limits are 32 events, 8 MiB and seven days. These files are
private diagnostics, not telemetry or release contents.

## Investigation and limits

The reported overnight interval contained no system sleep in the power log;
display sleep and other applications' sleep assertions kept the Mac awake.
Retained ordinary-use readings showed approximately 17–22% governed demand,
mainly from Trackpad/Actuator. They did not contain the reported 50% oscillation.
That cause remains unconfirmed. Longer smoothing reduces brief demand changes;
it does not prove a firmware or transaction problem has been fixed.

The user is in class and has quit Fandy. This delivery performs no live fan
writes, application launch, helper installation, workload stimulus or forced
sleep. Ordinary-use comparison, native sleep/wake and physical recovery acceptance
remain pending. Software fixtures do not establish physical compatibility.

## Tests-first record

New acceptance tests were written before production changes. Initial runs failed
on missing lifecycle/surge interfaces and old response/default values. Further
runtime regressions exposed expired-timer fallback, unnecessary sleep-time reads,
late telemetry, update admission during suspension, finished schedules, prior
fault resumption and a wake racing a revoked read. Each correction passed the
same assertions; tests were not weakened to accept the faulty behavior.

Coverage includes time-weighted bursts and sustained heating, cold/gap resets,
slider endpoints, legacy preferences, helper admission barriers and independent
partial restoration, duplicate notifications, revoked reads, failed wake,
application-group closure, elapsed deadlines and schedule changes during sleep.
Existing transaction, authentication, persistence, controller, watchdog and
hardware-adapter coverage is retained.

Final suite, sanitizer, signature and notarization results are recorded below
once verification completes. Private commands/logs remain under ignored `build`.

## Local verification

- Complete Swift suite: **480 passed** (72 hardware, 240 core, 168 application).
- Tool suite: **58 passed**.
- Address Sanitizer: the complete 479-test suite passed before the final
  suspended-write regression was added; that regression and the strengthened
  surge-byte-cap test additionally passed in a focused Address Sanitizer run.
- Thread Sanitizer: six existing concurrency checks and thirteen new sleep/surge
  checks passed; the final suspended-write regression additionally passed.
- One-job signed arm64 Release compilation passed.
- Developer ID app and DMG notarization/stapling, matching app/helper identities,
  hardened runtime, Gatekeeper app/image assessment, final mounted payload,
  privacy checks and image integrity passed.

Local artifact: `build/Distribution-0.3.1/Fandy-0.3.1-arm64.dmg`.
SHA-256: `3937a2a3e069b9c2ed809b44fadc41e6e09452a19bd97eabf75178ec5c877f3c`.

The installed app/helper remain unchanged and Fandy is closed. No 0.3.1 GitHub
release or updater-feed entry is published. Physical ordinary-use surge comparison,
verified native sleep/wake and any further other-Mac acceptance await later testing.
