import Foundation

/// Bounds work before it reaches the helper's serial hardware/watchdog queue.
/// Tickets are internal process authority, never decoded from an XPC payload.
public final class HelperRequestGate: @unchecked Sendable {
    public struct Ticket: Sendable, Hashable {
        fileprivate let id: UUID
        public let owner: UUID
        fileprivate let kind: Kind
    }
    fileprivate enum Kind: Sendable, Hashable { case ordinary, restoration, rejection }
    private struct Peer {
        var open = true
        var limiter = MessageRateLimiter()
        var ordinary = 0
        var restoration = false
        var rejection = false
    }
    private let lock = NSLock()
    private var peers: [UUID: Peer] = [:]
    private var tickets: [UUID: Ticket] = [:]
    private var ordinaryCount = 0
    private var restorationCount = 0
    private var rejectionCount = 0
    public init() {}

    public func connect(owner: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // Closed peers retain their slot until queued disconnect cleanup has run.
        guard peers.count < 8, peers[owner] == nil, !tickets.values.contains(where: { $0.owner == owner }) else { return false }
        peers[owner] = Peer(); return true
    }
    public func admit(owner: UUID, bytes: Int? = nil, now: Double) throws -> Ticket {
        lock.lock(); defer { lock.unlock() }
        guard var peer = peers[owner], peer.open else { throw ControlError.staleSession }
        if let bytes, !(1...Wire.maxBytes).contains(bytes) { throw ControlError.malformedMessage }
        let allowed = peer.limiter.allow(at: now)
        peers[owner] = peer
        guard allowed, peer.ordinary < 2, ordinaryCount < 4 else { throw ControlError.excessiveMessages }
        peer.ordinary += 1; peers[owner] = peer; ordinaryCount += 1
        return ticket(owner: owner, kind: .ordinary)
    }
    public func admitRestoration(owner: UUID) throws -> Ticket {
        lock.lock(); defer { lock.unlock() }
        guard var peer = peers[owner], peer.open else { throw ControlError.staleSession }
        // Independent of ordinary traffic/rate limits, bounded to one per connection.
        guard !peer.restoration, restorationCount < 8 else { throw ControlError.excessiveMessages }
        peer.restoration = true; peers[owner] = peer
        restorationCount += 1
        return ticket(owner: owner, kind: .restoration)
    }
    public func rejection(owner: UUID) -> Ticket? {
        lock.lock(); defer { lock.unlock() }
        guard var peer = peers[owner], peer.open, !peer.rejection, rejectionCount < 8 else { return nil }
        peer.rejection = true; peers[owner] = peer
        rejectionCount += 1
        return ticket(owner: owner, kind: .rejection)
    }
    public func isOpen(_ ticket: Ticket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return tickets[ticket.id] == ticket && peers[ticket.owner]?.open == true
    }
    public func finish(_ ticket: Ticket) {
        lock.lock(); defer { lock.unlock() }
        guard tickets.removeValue(forKey: ticket.id) != nil else { return }
        if ticket.kind == .ordinary { ordinaryCount -= 1 }
        if ticket.kind == .restoration { restorationCount -= 1 }
        if ticket.kind == .rejection { rejectionCount -= 1 }
        guard var peer = peers[ticket.owner] else { return }
        switch ticket.kind {
        case .ordinary: peer.ordinary -= 1
        case .restoration: peer.restoration = false
        case .rejection: peer.rejection = false
        }
        peers[ticket.owner] = peer
    }
    /// Exactly one caller schedules disconnect cleanup; queued requests become inert immediately.
    public func close(owner: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var peer = peers[owner], peer.open else { return false }
        peer.open = false; peers[owner] = peer; return true
    }
    public func disconnected(owner: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard peers[owner]?.open == false else { return }
        peers.removeValue(forKey: owner)
    }
    private func ticket(owner: UUID, kind: Kind) -> Ticket {
        let ticket = Ticket(id: UUID(), owner: owner, kind: kind)
        tickets[ticket.id] = ticket; return ticket
    }
}
