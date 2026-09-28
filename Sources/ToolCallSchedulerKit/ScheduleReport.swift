/// What happened to one call.
public enum ToolCallOutcome: Sendable, Equatable {
    case succeeded(String)
    case failed(String)
    /// Never started, because a call it declared a dependency on failed (directly or transitively).
    /// `blockedBy` names the call that actually failed.
    case skipped(blockedBy: String)

    public var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }
}

/// One call's result, returned in the batch's emission order so it can be sent straight back to
/// the provider as the turn's tool messages.
public struct ToolCallRecord: Sendable, Equatable {
    public let call: ScheduledToolCall
    public let outcome: ToolCallOutcome
    /// Zero-based order in which the call was started. `nil` for skipped calls.
    public let startOrder: Int?
}

public struct ScheduleReport: Sendable, Equatable {
    public let plan: SchedulePlan
    public let records: [ToolCallRecord]
    public let maxConcurrency: Int
    /// The most calls that were ever in flight at once.
    public let peakConcurrency: Int

    public var succeeded: Int { records.filter { $0.outcome.isSuccess }.count }
    public var failed: Int { records.filter { if case .failed = $0.outcome { return true }; return false }.count }
    public var skipped: Int { records.count - succeeded - failed }

    public func record(for callID: String) -> ToolCallRecord? {
        records.first { $0.call.id == callID }
    }
}
