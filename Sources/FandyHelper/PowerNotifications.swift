import Foundation
import IOKit
import IOKit.pwr_mgt
import FandyCore

// IOMessage.h: sys_iokit | sub_iokit_common | 0x280 / 0x300 / 0x270.
// Swift cannot import these nested C macros.
// Retained for the launch daemon's lifetime. No dependence on AppKit/user-session notifications.
final class PowerNotifications: @unchecked Sendable {
    let transition: (NativePowerEvent) -> Void
    var port: IONotificationPortRef?
    var notifier: io_object_t = 0
    var connection: io_connect_t = 0
    init(queue: DispatchQueue, transition: @escaping (NativePowerEvent) -> Void) throws {
        self.transition = transition
        connection = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &port, { context, _, message, argument in
            guard let context else { return }
            let power = Unmanaged<PowerNotifications>.fromOpaque(context).takeUnretainedValue()
            if message == 0xe0000280 { power.transition(.willSleep) }
            if message == 0xe0000300 { power.transition(.didWake) }
            if message == 0xe0000280 || message == 0xe0000270 {
                IOAllowPowerChange(power.connection, Int(bitPattern: argument))
            }
        }, &notifier)
        guard connection != 0, let port else { throw ControlError.helperUnavailable }
        IONotificationPortSetDispatchQueue(port, queue)
    }
    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if let port { IONotificationPortDestroy(port) }
        if connection != 0 { IOServiceClose(connection) }
    }
}
