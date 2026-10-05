# Apple Silicon compatibility — 0.2.0

Requires an arm64 Mac and macOS 15 or later. This release targets MacBook Pro, including base, Pro and Max variants. No M1–M4 machine or other M5 variant was available for physical testing. Reference-supported means a reviewed source recipe plus runtime validation, not physical certification.

| Family | Compiled notebook identifiers | Evidence | Fan interfaces | Temperature-profile requirements |
| --- | --- | --- | --- | --- |
| M1 | MacBookPro17,1; MacBookPro18,1–4 | Reference-supported | Direct per-fan mode; validated Ftst if protected | Published M1 CPU regions from both clusters and GPU regions |
| M2 | Mac14,5; 6; 7; 9; 10 | Reference-supported | Direct or bounded Ftst | Published M2 CPU regions from both clusters and GPU regions |
| M3 | Mac15,3; 6–11 | Reference-supported | Direct or bounded Ftst | Explicit M3 Te/Tf CPU and Tf GPU members; no prefix guessing |
| M4 | Mac16,1; 5–8 | Reference-supported; priority generation | Direct if accepted; Ftst handover for protected mode 3 / result 0x82 | Explicit CPU regions; separate base versus Pro/Max GPU anchors |
| M5 | Mac17,2; 6–9 | Mac17,9 locally tested; others reference-supported | Mac17,9 retains its tested lowercase direct recipe; other variants require reviewed metadata | Mac17,9 retains its full conservative envelope; other variants use published M5 regions |
| Other / Intel / inconsistent identity | None | Unsupported for writes | No control authority | Independent readable temperature monitoring remains available |

Model roster: [Apple notebook identification](https://support.apple.com/en-us/108052), reviewed 2026-10-04. Apple Silicon capability, model identifier and chip brand/generation are checked separately. A supported model identifier alone does not grant a lease.

## Sensor membership and profile eligibility

The compiled arrays derive from [Stats sensor definitions at 9ceb6e3](https://github.com/exelban/stats/blob/9ceb6e3b20001c4102f473c5dc3e96b388a77da9/Modules/Sensors/values.swift), under MIT; see THIRD_PARTY_NOTICES.md and the bundled license. Only explicit source-defined members are probed during initialization. Source-table members absent with the SMC not-found result are documented variant omissions; corrupt or failed candidates block chip qualification. Selected membership and data types are frozen for that process. Every selected member must remain present, correctly typed, finite and fresh. Average display groups and maximum control groups are distinct. Core counts are never used to truncate the table.

System remains the startup/wake policy. Max requires supported fan metadata and each fan's own bounds, without temperature qualification. System+, Gaming and chip-only custom curves additionally require complete CPU/GPU control groups. Cool Chassis, Silent and enabled chassis curves require Trackpad Ts0P, Actuator Ts1P, Left TaLP, Top proximity TaTP and Right TaRF. Missing comfort inputs receive their own unavailable reason; CPU does not substitute. Historical comfort descriptors provide reference support, not a surface-temperature calibration on every model. Top is explicitly a proximity proxy. Charger and power-supply candidates remain informational. These comfort policies preserve their separate temperature scales and max-demand aggregation.

## Fan metadata and transactions

Runtime discovery accepts one or two independently bounded fans; no equal-RPM assumption. Mode keys may be F?md or F?Md, but ambiguous aliases are rejected. Modes are ui8; RPM targets may be little-endian flt4 or legacy big-endian fpe2. ioft is not admitted for control. Writable metadata is compared on the actual writer connection before each command. Unknown modes, types or permissions block activation. Invalid target metadata can still leave reviewed automatic release available.

Direct acquisition admits, acknowledges and promptly targets each fan independently before admitting the next fan. Reference adapters poll accepted mode commands every 50 ms within the original seven-second deadline; they never rewrite accepted admission commands. Only source-described protected mode 3 or command rejection 0x82 can enter the Ftst adapter. That adapter releases partial direct acquisition, asserts Ftst, waits at most seven seconds for automatic admission, then enters manual mode and verifies target acknowledgement. Cancellation, fresh complete required sensors, thermal-pressure validation, ownership checks and deadline checks surround the sequence. System/disconnect revoke the operation at XPC ingress; queued stale work cannot reacquire control afterward. No retries of alternative keys or target clearing occur.

Release attempts every fan even after a partial failure, clears and reads back Ftst independently, and re-reads every mode after global release. Protected firmware System mode 3 is already non-manual: release does not send an unsupported mode write to it, but global release and final mode verification still run. Ftst loss during an owned lease aborts instead of fighting another controller.

Fan references: [Stats SMC at the pinned revision](https://github.com/exelban/stats/blob/9ceb6e3b20001c4102f473c5dc3e96b388a77da9/SMC/smc.swift), [ThermalForge 93ed7d2](https://github.com/ProducerGuy/ThermalForge/tree/93ed7d2df231b079704156b5ae67654a50d31f62), and [SMC interoperability research](https://github.com/agoodkind/macos-smc-fan/blob/main/docs/research.md). These are undocumented userspace interoperability observations, not an Apple fan-control API guarantee.

## Honest limits

Ftst changes normal thermal-controller ownership and can suppress normal reclaim. Custom control replaces normal Apple fan demand; no Apple fan-floor behavior is claimed. Fandy cannot guarantee the independence of Apple's emergency behavior on an inaccessible model. A dead or blocked helper cannot execute its watchdog; launchd restart restores before sensor initialization, but restart and successful hardware I/O are not guaranteed. Unknown ownership, sensor failure, invalid metadata or transaction failure revokes control and attempts verified release; a failed release is reported honestly.

Synthetic fixtures exercise source-backed command construction for M1–M5, one/two-fan topologies, different bounds, types, uppercase/lowercase keys, protected mode, timeouts, cancellation, partial failures, failed global release and startup recovery. They are labeled synthetic and contain no captured foreign-machine measurements. Only Mac17,9 is physically tested. The deployment target and unsigned CI build matrix check compilation; they do not demonstrate older-OS hardware behavior or inaccessible-Mac compatibility.

## M2 startup and acknowledgement — build 21

Already-automatic reference mode 0/3 avoids a redundant protected mode write. Ftst release and final mode verification remain required. Hardware initialization failures retain a live authenticated status listener; fixed transient retries and structured diagnostic codes distinguish missing approval from unavailable hardware. This addresses identified failure paths, but the reported M2 Pro failure has no diagnostic capture and is **not physically verified fixed**. Friend acceptance remains necessary.

PR #1 contributes physical Mac14,9 / M2 Pro observations on macOS 27.0.1: temperature profiles, curve edits and System handback worked after bounded mode-readback polling. The contributor measured quit/disconnect/heartbeat handback at approximately 0.35/0.54/10.04 seconds using separately signed app/helper identities. This is **contributor-tested direct-interface evidence**, not local certification or proof that the official distribution identity starts correctly on that machine. Neither M2 sleep/wake, root-helper termination nor Ftst acquisition was retested. M1/M3/M4 and other M5 variants retain reference-supported status; delayed-acknowledgement fixtures exercise their existing adapters without changing sensor groups or admitting new keys. The `locallyTested` adapter flag remains exclusive to the existing M5 recipe.

Reference release waits at most one second per commanded fan, then retains global release and independent final readback. Already-automatic observations still do not claim release from manual ownership. Silent is the former School built-in; its stable `school` ID preserves automation and saved selection.
