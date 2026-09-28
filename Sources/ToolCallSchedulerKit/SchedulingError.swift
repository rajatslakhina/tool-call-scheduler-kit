/// Reasons a batch cannot be scheduled at all. Each one is a malformed batch, not a tool failure,
/// so nothing in the batch runs.
public enum SchedulingError: Error, Equatable, Sendable {
    /// Two calls share an id, so their results could not be returned to the provider unambiguously.
    case duplicateCallID(String)
    /// A call depends on an id that is not in the batch.
    case unknownDependency(callID: String, dependsOn: String)
    /// Declared dependencies form a cycle. Lists every call in or behind the cycle, in emission order.
    case dependencyCycle(involving: [String])
    /// `maxConcurrency` must be at least 1.
    case invalidConcurrency(Int)
}
