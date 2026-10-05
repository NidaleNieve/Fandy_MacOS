# Reference projects and attribution

Fandy's implementation was authored independently. It vendors no third-party runtime, framework, fan-control source, proprietary application code, Apple binary or kernel driver. ReferenceSensorKeys.swift adapts the published MIT-licensed Stats sensor-key arrays, with copyright and full license retained. Published protocol observations and sensor-key facts were used as interoperability references. Full permissive reference license notices are preserved in `docs/licenses/` and included in the app bundle for attribution.

| Project / inspected revision | License checked | Use |
| --- | --- | --- |
| [ProducerGuy/ThermalForge](https://github.com/ProducerGuy/ThermalForge), 93ed7d2df231b079704156b5ae67654a50d31f62 | MIT; Copyright 2026 ProducerGuy | Inspected safety/watchdog/daemon/SMC architecture. Concepts informed the design; no source copied. [Notice](docs/licenses/ThermalForge.txt). |
| [exelban/stats](https://github.com/exelban/stats), 9ceb6e3b20001c4102f473c5dc3e96b388a77da9 | MIT; Copyright 2019 Serhiy Mytrovtsiy | M1–M5 candidate sensor arrays adapted with attribution; fan interface and handover sequence reviewed. No adapter implementation copied. [Notice](docs/licenses/stats.txt). |
| [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan), 31a1feae0c4999ebd8cdddfbd90d2c98182091b8 | MIT for original code/research; explicit exclusion of Apple intellectual property | Protocol and mode-behavior research only; no decompiled Apple code/binaries included. [Exact scope/legal notice](docs/licenses/macos-smc-fan.txt). GitHub's license classifier says NOASSERTION because the file contains additional scope text; the file itself identifies MIT for the original work. |
| [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC), b5c62c2311540c529c00996d0d9cec33f8e571c9 | BSD-3-Clause; Copyright 2017 vit9696 | Historical sensor-name reference only. No kernel component/code used. [Notice](docs/licenses/VirtualSMC.txt). |
| [hholtmann/smcFanControl](https://github.com/hholtmann/smcFanControl) | GPL-2.0 | License/history checked; no source incorporated. |
| [yujitach/MenuMeters](https://github.com/yujitach/MenuMeters), e91b746debd15777012968a4d247a074d10402f6 | GPL-2.0 | Licence/provenance checked. No source incorporated. Stats' HID reader cites this ancestry; Fandy's optional adapter is independently authored from observed interface signatures and temperature-event facts. |

TG Pro and Macs Fan Control are proprietary reference applications. TG Pro's public user guide and the user's authorized numeric temperature CSV were used; no proprietary source/resources were reverse engineered or copied. Apple documentation and installed SDK declarations informed SMAppService, NSXPC requirements, IOKit power notifications and ProcessInfo thermal state usage.

Fandy's original work is released under the [MIT license](LICENSE). Third-party notices retain their original licenses. No license here grants rights to Apple's proprietary implementations or guarantees that an undocumented interface is supported. The included permissive license texts are the original projects' notices, not a claim that those authors endorse or qualify Fandy's hardware behavior.

Additional source inspection on 2026-10-01: [iSMC](https://github.com/dkorunic/iSMC), revision `db76170a7ede0386fd10143b2e8f6c5c127188aa`, LICENSE confirms GPLv3. Sensor descriptor facts and two reported M5 Pro raw catalogs were reviewed for provenance and conflicts. Only broad naming candidates for independently discovered keys are noted; no GPL implementation or descriptor table was copied or incorporated. MacMonitor's SENSORS documentation appeared in search results and its LICENSE is MIT; its different-model descriptions were not adopted as M5 identity proof and no code/data was incorporated. Reference: https://github.com/ryyansafar/MacMonitor.

## Sparkle 2.10.0

Fandy uses [Sparkle](https://github.com/sparkle-project/Sparkle/tree/2.10.0) for signed application updates. Its license and bundled component notices are reproduced in [docs/licenses/Sparkle.txt](docs/licenses/Sparkle.txt).
