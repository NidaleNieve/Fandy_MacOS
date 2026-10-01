// Negative authentication probe. This process can only ask for status; no mode/RPM interface.
import Foundation

@objc protocol StatusProbe {
    func status(withReply reply: @escaping (Data?, String?) -> Void)
}
final class Outcome: @unchecked Sendable {
    let lock = NSLock()
    let semaphore = DispatchSemaphore(value: 0)
    private var result: [String: String]?
    func finish(_ value: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        guard result == nil else { return }
        result = value; semaphore.signal()
    }
    func value() -> [String: String]? { lock.lock(); defer { lock.unlock() }; return result }
}
func runProbe() {
    let outcome = Outcome()
    let connection = NSXPCConnection(machServiceName: "is.dsr.fandy.fan-helper", options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: StatusProbe.self)
    connection.resume()
    let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
        let error = error as NSError
        outcome.finish(["result": "connectionRejected", "domain": error.domain, "code": String(error.code)])
    } as! StatusProbe
    proxy.status { @Sendable data, error in
        outcome.finish(["result": data == nil ? "remoteError" : "unexpectedlyAccepted", "message": error ?? ""])
    }
    if outcome.semaphore.wait(timeout: .now() + 4) == .timedOut {
        outcome.finish(["result": "timeout"])
    }
    connection.invalidate()
    if let result = outcome.value(), let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        exit(result["result"] == "connectionRejected" ? 0 : 1)
    }
    exit(1)

}
runProbe()
