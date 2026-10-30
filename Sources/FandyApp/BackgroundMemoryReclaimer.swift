import Foundation
import Darwin

/// A single deferred trim after closing UI returns already-freed allocator pages
/// to macOS. It neither evicts live objects nor runs on a periodic idle timer.
@MainActor final class BackgroundMemoryReclaimer {
    static let shared = BackgroundMemoryReclaimer()
    private let pause: () async -> Void
    private let release: () -> Void
    private var pending: Task<Void, Never>?
    init(pause: @escaping () async -> Void = { try? await Task.sleep(for: .seconds(1)) },
         release: @escaping () -> Void = { _ = malloc_zone_pressure_relief(nil, 0) }) {
        self.pause = pause; self.release = release
    }
    func schedule() {
        guard pending == nil else { return }
        pending = Task { [weak self] in
            guard let self else { return }
            await pause(); release(); pending = nil
        }
    }
}
