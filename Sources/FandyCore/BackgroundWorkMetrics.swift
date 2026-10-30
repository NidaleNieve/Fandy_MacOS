import Foundation
import Darwin

public enum BackgroundWorkPhase: String, Codable, Sendable, CaseIterable {
    case sampling, controllerScan, smc, statusEncoding
}
public struct BackgroundWorkSample: Codable, Sendable, Equatable {
    public let phase: BackgroundWorkPhase
    public let calls: UInt64
    public let cpuNanoseconds: UInt64
}
/// Fixed, passive counters; no history, caller timing, keys or hardware authority.
/// Phases may nest (SMC is included in sampling), so their totals are not additive.
public final class BackgroundWorkMetrics: @unchecked Sendable {
    public static let shared = BackgroundWorkMetrics()
    private let lock = NSLock()
    private let clock: @Sendable () -> UInt64
    private var totals: [BackgroundWorkPhase: (calls: UInt64, cpu: UInt64)] = [:]
    public init(clock: @escaping @Sendable () -> UInt64 = {
        var time = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0 else { return 0 }
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
    }) { self.clock = clock }
    public func measure<T>(_ phase: BackgroundWorkPhase, operation: () throws -> T) rethrows -> T {
        let start = clock()
        defer {
            let end = clock(), elapsed = end >= start ? end - start : 0
            lock.lock()
            let old = totals[phase] ?? (0, 0)
            let next = old.cpu.addingReportingOverflow(elapsed)
            totals[phase] = (old.calls == .max ? .max : old.calls + 1, next.overflow ? .max : next.partialValue)
            lock.unlock()
        }
        return try operation()
    }
    public func snapshot() -> [BackgroundWorkSample] {
        lock.lock(); defer { lock.unlock() }
        return BackgroundWorkPhase.allCases.compactMap { phase in
            totals[phase].map { BackgroundWorkSample(phase: phase, calls: $0.calls, cpuNanoseconds: $0.cpu) }
        }
    }
}
