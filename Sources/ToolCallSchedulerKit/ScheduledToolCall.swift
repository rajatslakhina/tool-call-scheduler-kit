/// One tool call a model emitted in a turn, as the scheduler sees it.
///
/// `id` is the provider's call identifier. Tool results go back to the provider keyed by this
/// value, so it must be unique inside one batch. `arguments` is the decoded argument object,
/// flattened to strings, which is all the scheduler needs to derive resource keys.
public struct ScheduledToolCall: Sendable, Equatable, Hashable {
    public let id: String
    public let toolName: String
    public let arguments: [String: String]
    /// Ids of calls in the same batch whose result this call consumes. Most providers have no way
    /// to express this, so it is usually empty and ordering comes from declared effects instead.
    public let dependsOn: [String]

    public init(id: String, toolName: String, arguments: [String: String] = [:], dependsOn: [String] = []) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.dependsOn = dependsOn
    }
}
