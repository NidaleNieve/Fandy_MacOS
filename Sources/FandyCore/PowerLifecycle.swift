/// System sleep is distinct from display sleep. No state grants hardware authority.
public enum PowerLifecycle: String, Sendable { case awake, suspending, suspended, resuming }
public enum NativePowerEvent: Sendable { case willSleep, didWake }
