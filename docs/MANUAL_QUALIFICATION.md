# Bounded manual qualification preparation

The admission and deadline model is implemented and tested, but is **not connected to XPC or a physical writer**. This prepares the next gate without bypassing the all-requested-sensors requirement. The registered helper remains restoration-only. No manual request was made during this development session.

## Authority and admission

`HardwareCapabilities.canQualifyManual` requires the exact compiled model, `manualQualification` stage, verified topology, all twelve required sensor roles, and the already-proven automatic-restoration gate. It does not require production manual-transaction proof, because that is the purpose of qualification. It cannot admit a production profile lease. Observation, restoration and production stages cannot invoke this test authority. Preferences and received helper capability reports cannot create local authority.

`ManualQualificationPlan` accepts only the helper's own fresh snapshot and automatic-restoration result. It requires automatic mode on every fan, qualified finite readings for every required role, nominal/fair system pressure, and acquisition age at most two seconds. A conservative 75°C diagnostic ceiling applies during tests; it is not an Apple critical-temperature assertion.

Targets are computed independently as **fresh actual RPM + 200**. The complete request must fit each fan's actual minimum/maximum before either fan is admitted. If a fan is stopped, or lacks the upward margin, the whole trial is skipped: no substitution of minimum RPM, downward clamp, or partial test. Apple currently may stop the fans, so a future qualification session must wait for normal Apple-controlled spinning rather than force a different first-test target.

## Deadline and revocation

The first trial has an absolute five-second deadline. Recovery trials have an absolute fifteen-second deadline and a ten-second heartbeat timeout. Time begins at admission, before any future mode/target transaction. Heartbeats never move the deadline. A session is one-use; once stopped, it cannot reactivate. A future helper dispatcher must also prevent repeated calls from extending a trial and require verified restoration before admitting any new session.

The pure session revokes on expiry, owned disconnect, sleep/wake, malformed owned heartbeat, absent/stale/unqualified/nonadvancing readings, thermal uncertainty, changing fan bounds/topology, ownership conflict, or a non-finite/backwards clock. A different authenticated connection cannot renew the session. Fresh acquisitions at constant temperatures remain valid. Reusing an acquisition is allowed only while fresh and unchanged.

Revocation is a decision to restore; it does **not** claim physical handback. The future dispatcher must execute restoration, retain per-fan results and independently verify both modes. The physical writer's metadata, target encoding, stale-target behavior and transaction order still need review after sensor qualification. This model grants no authority to the existing generic profile API and does not prescribe an unverified hardware sequence.

## Validation and remaining gates

Eleven new Swift tests cover stage/model separation, every missing sensor role, restoration proof, independent fan bounds, stopped/ceiling-limited fans, sensor/thermal admission, fixed deadlines, heartbeat expiration, connection ownership, malformed messages, topology changes, acquisition freshness and lifecycle revocation. All physical manual-mode and target functions still reject requests.

Next: resolve [chip coverage](SENSOR_EVIDENCE.md) and [sensor identity](SENSOR_EVIDENCE.md), review an injected-transport physical writer, add the dedicated authenticated qualification operation, then perform the five-second upward trial with immediate verified release. Live SIGKILL/disconnect/heartbeat/restart/sleep and the full recovery matrix remain mandatory before profiles. A dead, blocked or suspended helper cannot execute any timer; no bounded model removes that residual limitation.
