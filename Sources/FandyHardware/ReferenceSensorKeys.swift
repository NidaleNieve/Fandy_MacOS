// Sensor-key definitions adapted from exelban/stats, MIT.
// Copyright (c) 2019 Serhiy Mytrovtsiy. Full notice: docs/licenses/stats.txt.
// Pinned revision 9ceb6e3b20001c4102f473c5dc3e96b388a77da9, Modules/Sensors/values.swift.
// These are published region candidates, not physical coverage measurements by Fandy.
enum ReferenceSensorKeys {
    static let m1Efficiency = ["Tp09", "Tp0T"]
    static let m1Performance = ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
    static let m1Gpu = ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
    static let m2Efficiency = ["Tp1h", "Tp1t", "Tp1p", "Tp1l"]
    static let m2Performance = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
    static let m2Gpu = ["Tg0f", "Tg0j"]
    static let m3Efficiency = ["Te05", "Te0L", "Te0P", "Te0S"]
    static let m3Performance = ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
    static let m3Gpu = ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
    static let m4Efficiency = ["Te05", "Te0S", "Te09", "Te0H"]
    static let m4Performance = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
    static let m4Gpu = ["Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
    static let m5Performance = ["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
    static let m5SuperCores = ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"]
    static let m5Gpu = ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]
    static let m4BaseGPU = ["Tg0G", "Tg0H"]
    static let m4ProMaxGPU = ["Tg1U", "Tg1k"]
}
