# Research and implementation decisions

Research preceded implementation. The original manual-control gates remain binding. On2026-10-01 the user approved automatic restoration before sensor qualification. Source inspection is evidence of another program's implementation, not proof of Apple firmware behavior.

## Primary references

- [ThermalForge source](https://github.com/ProducerGuy/ThermalForge): MIT source inspected for userspace SMC, daemon, polling, watchdog and thermal guards. It uses a socket daemon, a 15-second watchdog checked every five seconds, and a 95°C guard. Some CLI manual operations can bypass supervised leases; reset paths may ignore per-fan errors; Max has a hard-coded fallback; wake can reapply stale settings. Fandy adopts the fallback philosophy while requiring explicit verified release and fresh initialization.
- [macos-smc-fan research](https://github.com/agoodkind/macos-smc-fan): modern generation-dependent mode behavior, including M5 lowercase F%dmd, mode0/1, firmware system state3 and absent Ftst on its tested M5. Do not transfer its tested machine's behavior unqualified to Mac17,9. No M1–M4 unlock/Ftst sequence or thermal-service manipulation is included here.
- [Stats sensor list](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift): Apple Silicon generation-specific key tables, including M5 chip and Airflow Left/Right candidates. Sensor tables are model-sensitive.
- [VirtualSMC key-name document](https://github.com/acidanthera/VirtualSMC/blob/master/Docs/SMCSensorKeys.txt): useful historical Trackpad/Actuator/proximity naming, not proof of M5 identity.
- [TG Pro's guide](https://www.tunabellysoftware.com/support/tgpro_tutorial/): current M5 support, sensor/logging capabilities and its fan override behavior. Its internal mapping implementation is proprietary and was not inspected.
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [daemon registration](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)): modern macOS bundle-based launch daemon registration and native approval.
- [NSXPCListener code-signing requirements](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)), [NSXPCConnection requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)): public macOS13+ mutual requirements, confirmed against installed SDK headers.
- [ProcessInfo thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property): system thermal pressure as a conservative handback signal. SDK IOPMLib/IOMessage declarations specify will-sleep acknowledgement and wake behavior.

Licenses for every inspected project are recorded in THIRD_PARTY_NOTICES. No GPL implementation was incorporated. Optional HID discovery was independently authored and narrowed to vendor temperature events.

## Decisions covering the requested plan

1. **SMC architecture:** AppleSMC userspace IOKit connection, selector2, reverse-engineered80-byte transaction, commands5/read,8/key enumeration,9/metadata. Writer is private to the helper; discovery library has no writes.
2. **References/licensing:** ThermalForge, Stats, macos-smc-fan, VirtualSMC; GPL provenance/history checked for smcFanControl/MenuMeters. Permissive notices preserved; no proprietary code copied.
3. **M5 discovery:** enumerate #KEY and metadata; log typed raw values and per-fan metadata; compare contemporaneous authorized TG Pro numeric temperatures. Use optional temperature-only HID enumeration as supplemental evidence.
4. **Trackpad/Actuator:** Ts0P/Ts1P are supported candidates with historical names and contemporaneous readings. Qualification status remains explicit.
5. **Airflow L/T/R:** TaLP/TaTP/TaRF candidates; independent Left/Right names available, Top identity still unresolved. Do not put all raw chassis temperatures on one scale.
6. **Proximity:** TCHP/TPSP/TW0P candidates, corroborated numerically. Display/log only initially; charging heat alone cannot drive comfort demand.
7. **Chip aggregation:** explicit generation/model candidate membership, average display and peak control, max(CPU peak,GPU peak). Membership/coverage must be verified; prefix-based categorization is forbidden.
8. **Fans:** FNum then each fan's Ac/Mn/Mx/Tg and typed mode. Every fan independently bounded, no common max constant or guessed mode casing. Apple stopped-fan behavior distinct from spinning min.
9. **Manual mode:** not enabled until automatic restoration is proven. Research suggests custom manual demand replaces stock demand; M5-specific writer must be qualified before use.
10. **Automatic release:** revoke lease, attempt all fans, mode0 readback, never clear target, final verification. Firmware state3 remains unqualified and is not written or counted as automatic. No success on partial failure.
11. **Apple override/floor:** no verified minimum-floor mechanism that preserves higher Apple demand. Do not fake it; independent guards/watchdog are essential if manual mode is later enabled.
12. **Privilege/XPC:** ordinary GUI, tiny SMAppService root daemon, four narrow methods; public mutual exact identifier/Team requirements. No arbitrary command/key/path API.
13. **Watchdog/crashes:** validated requests heartbeat1Hz, ten-second lease,500ms checks, connection-owned UUID. Helper startup always restores; GUI death expires; root-helper hang remains an explicit residual risk.
14. **Power lifecycle:** GUI NSWorkspace reset plus independent root IOPM notifications; release before sleep/wake, no saved-profile auto resume; logout/reboot persist no manual state.
15. **Sensor failure/high temperature:** invalid/stale/missing data returns Apple ownership; constant valid temperatures are not falsely rejected. Serious/critical/unknown ProcessInfo pressure returns Apple. Immutable chip guard requests max at85°C as an app policy, never a claimed Apple critical threshold.
16. **Data model:** versioned local profiles, immutable fundamental IDs, defaults/reset, user CRUD/reorder, bounded atomic archive with backup/corrupt preservation; previous selection never restores control.
17. **Curves:** finite ordered unique temperatures, monotonic bounded percentages, linear interpolation and clamped endpoints; invalid editor drafts preserve last valid policy.
18. **Aggregation/governor:** max independent chip/Trackpad/Actuator/hottest Airflow/floor/guard requests. Fast rise, slow smoothed fall, deadband, upward safety bypass; automatic at idle for System+/School.
19. **Comfort/gaming:** initial editable comfort nodes use the supplied27/25/33 comfortable and31/29/43–44 warmer observations. Gaming becomes strong near80 and maximal by85. Actual acoustic/light-workload/gaming calibration is pending.
20. **Deployment/UI:** macOS15+ permits native editor launch suppression; this keeps startup in the menu bar. Earlier proposed macOS14 support was revised because SceneBuilder cannot conditionally apply this modifier. Primary M5 hardware supports the requirement.
21. **Tests/gates:** pure/model and native view-model tests, deterministic mock scenarios, actual read-only discovery, then restoration-only proof, modest manual, live GUI SIGKILL and physical failures, then custom curves. No screenshot/GUI automation.

## Known uncertainties

Unresolved Mac17,9 sensor membership/Top identity, actual writable firmware semantics, target-clear behavior under automatic ownership, independent Apple emergency protections during manual mode, system state3 meaning under load, practical sleep/wake/reboot behavior, blocked I/O latency, helper crash recovery timing and acoustic defaults. These uncertainties are explicit blockers to physical control, not assumptions hidden behind successful compilation.

## Additional sensor evidence review — 2026-10-01

[iSMC sensor descriptors](https://github.com/dkorunic/iSMC/blob/db76170a7ede0386fd10143b2e8f6c5c127188aa/src/temp.txt) provide broad-platform `TPSP` Power Supply Proximity and Apple `TaTP` Ambient Top Proximity naming candidates. Its GPLv3 license was checked before source inspection; no implementation or descriptor table was copied. These interoperability facts add provenance to the existing independently discovered keys, but the broad labels are not exact Mac17,9 qualification. Its different-generation SSD/Trackpad descriptions also demonstrate why transferring labels blindly is unsafe. Its two M5 Pro raw reports establish observed key presence on reported Pro machines, without an exact model/firmware identity proof.

Read-only `ioreg -a -l -p IODeviceTree` inspection on this Mac found a thermal `temp-sensor` property containing internal `Tp` and `Tm` labels. It did not provide friendly Trackpad/Airflow/proximity names or a mapping to four-character SMC keys. The single `smctempsensor0` reference also did not identify the required mappings. Only filtered thermal property names/types and printable thermal labels were retained; no binary firmware, serial-number values or unrelated device properties were saved. Omitting `-l` hides firmware properties and cannot support a claim that no descriptions exist.

The [chip coverage audit](SENSOR_EVIDENCE.md) now compares the full published domains with wider enumerated families using the existing 871-record session. Unselected `Tm` and `Tg` readings sometimes exceed current informational peaks. This is an explicit coverage question, not authority to use every prefix as a chip safety signal. No extra stimulus or idle-recording loop was run. Resolve membership and acquisition timing before granting peak coverage.


## Additional source check during recovery preparation

[mactop temperature classification](https://github.com/metaspartan/mactop/blob/8dbfaaed7426cff3bcfbcb7951a2e15dfb6d1667/internal/app/ioreport.m) was inspected after checking its MIT license. It classifies broad key prefixes and labels the Ts family as Super-core temperatures when Super cores exist. That conflicts with the independently discovered chassis candidates and does not establish current-model CPU or chassis identities. No source was copied or runtime dependency introduced. Further narrowly scoped TG Pro diagnostics and filtered thermal IORegistry descriptions yielded no missing identity mappings; they do not change qualification.
