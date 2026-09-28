/// Where a resource key comes from: a fixed resource, narrowed by one argument's value when the
/// call supplies it.
public struct ResourceSelector: Sendable, Equatable {
    public let resource: String
    public let instanceArgument: String?

    public init(_ resource: String, instanceArgument: String? = nil) {
        self.resource = resource
        self.instanceArgument = instanceArgument
    }

    func key(for call: ScheduledToolCall) -> ResourceKey {
        ResourceKey(resource, instance: instanceArgument.flatMap { call.arguments[$0] })
    }
}

/// The declared effects of one tool, written once next to its definition.
public struct ToolEffectRule: Sendable, Equatable {
    public let reads: [ResourceSelector]
    public let writes: [ResourceSelector]
    public let isBarrier: Bool

    public init(reads: [ResourceSelector] = [], writes: [ResourceSelector] = []) {
        self.init(reads: reads, writes: writes, isBarrier: false)
    }

    private init(reads: [ResourceSelector], writes: [ResourceSelector], isBarrier: Bool) {
        self.reads = reads
        self.writes = writes
        self.isBarrier = isBarrier
    }

    public static let pure = ToolEffectRule()
    public static let barrier = ToolEffectRule(reads: [], writes: [], isBarrier: true)

    func effects(of call: ScheduledToolCall) -> ToolEffects {
        if isBarrier { return .barrier }
        return ToolEffects(
            reads: Set(reads.map { $0.key(for: call) }),
            writes: Set(writes.map { $0.key(for: call) })
        )
    }
}

/// Maps tool names to their effect rules.
///
/// A tool with no rule is treated as a barrier. That is deliberately the slow answer: a tool
/// nobody described might do anything, and running it alongside a write is the bug this package
/// exists to prevent.
public struct ToolEffectCatalog: Sendable {
    private var rules: [String: ToolEffectRule]

    public init(_ rules: [String: ToolEffectRule] = [:]) {
        self.rules = rules
    }

    public mutating func register(_ toolName: String, _ rule: ToolEffectRule) {
        rules[toolName] = rule
    }

    public func isDeclared(_ toolName: String) -> Bool {
        rules[toolName] != nil
    }

    public func effects(of call: ScheduledToolCall) -> ToolEffects {
        (rules[call.toolName] ?? .barrier).effects(of: call)
    }
}
