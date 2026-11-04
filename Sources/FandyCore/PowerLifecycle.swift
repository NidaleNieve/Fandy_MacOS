/// System sleep states; display sleep does not enter them.
public enum PowerLifecycle: String, Sendable { case awake, suspending, suspended, resuming }
public enum NativePowerEvent: Sendable { case willSleep, didWake }
