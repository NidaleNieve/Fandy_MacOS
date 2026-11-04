# Third-party notices

Fandy's original code is released under the [MIT license](LICENSE). It bundles Sparkle for application updates and adapts MIT-licensed Stats sensor-key arrays. The following notices are included in the app bundle alongside Fandy's license.

## Bundled and adapted code

| Project | Use | License |
| --- | --- | --- |
| [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/tree/2.10.0) | Signed application updates, including its bundled components. | [Sparkle and component notices](docs/licenses/Sparkle.txt) |
| [Stats](https://github.com/exelban/stats/tree/9ceb6e3b20001c4102f473c5dc3e96b388a77da9) | Apple Silicon sensor arrays adapted in `ReferenceSensorKeys.swift`; copyright 2019 Serhiy Mytrovtsiy. | [MIT](docs/licenses/stats.txt) |

## Interoperability references

These projects informed protocol, sensor or architecture research. Their fan-controller implementations are not bundled in Fandy.

| Reference | Inspected revisions / scope | Retained notice |
| --- | --- | --- |
| [ThermalForge](https://github.com/ProducerGuy/ThermalForge) | `93ed7d2df231b079704156b5ae67654a50d31f62`, `42bb5345bc0a8d41a9c47719c3ceb0fbc7249687`; helper, watchdog and SMC architecture. | [MIT](docs/licenses/ThermalForge.txt) |
| [Stats](https://github.com/exelban/stats) | Sensor revision above and `88d5359ad3466efaa16985646a0bb15c6599109f`; mode precedence and handover research. | [MIT](docs/licenses/stats.txt) |
| [macos-smc-fan](https://github.com/agoodkind/macos-smc-fan/tree/31a1feae0c4999ebd8cdddfbd90d2c98182091b8) | Protocol and mode-behavior research. No decompiled Apple code or binaries included. | [MIT with original scope notice](docs/licenses/macos-smc-fan.txt) |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC/tree/b5c62c2311540c529c00996d0d9cec33f8e571c9) | Historical sensor-name reference; no kernel component incorporated. | [BSD-3-Clause](docs/licenses/VirtualSMC.txt) |

License/provenance review also covered [smcFanControl](https://github.com/hholtmann/smcFanControl) (GPL-2.0), [MenuMeters](https://github.com/yujitach/MenuMeters/tree/e91b746debd15777012968a4d247a074d10402f6) (GPL-2.0), and [iSMC](https://github.com/dkorunic/iSMC/tree/db76170a7ede0386fd10143b2e8f6c5c127188aa) (GPLv3). Their source implementations and descriptor tables were not incorporated. Fandy's HID adapter was independently authored from interface signatures and temperature-event facts. MacMonitor documentation was considered during naming research; no code or data was incorporated.

TG Pro's public documentation and authorized temperature exports were development references. No proprietary application source, mapping database, Apple binary or kernel driver is distributed. Normal operation has no TG Pro dependency. Reference authors do not certify Fandy's hardware behavior; undocumented interfaces remain subject to change.
