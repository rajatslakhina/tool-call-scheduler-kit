/// Why one call has to wait for another.
public enum EdgeReason: Sendable, Equatable {
    /// The later call declared it consumes the earlier call's result. Failure propagates.
    case dependency
    /// The two calls touch overlapping resources and at least one writes. Emission order is kept;
    /// failure does not propagate, because the second call never needed the first one's output.
    case resourceConflict([String])
    /// One of the two calls has undeclared effects.
    case barrier

    var propagatesFailure: Bool {
        self == .dependency
    }
}

/// "`to` may not start until `from` has finished."
public struct ScheduleEdge: Sendable, Equatable {
    public let from: String
    public let to: String
    public let reason: EdgeReason
}

struct IndexedEdge: Sendable, Equatable {
    let from: Int
    let to: Int
    let reason: EdgeReason
}

/// A batch's ordering constraints, resolved before anything runs.
///
/// `waves` is the layering you would get with unlimited concurrency: every call in wave `n` has
/// all of its predecessors in waves `0..<n`. The executor does not wait for a whole wave to
/// finish before starting the next one; waves are the plan's shape, not its timetable.
public struct SchedulePlan: Sendable, Equatable {
    public let calls: [ScheduledToolCall]
    public let waves: [[String]]
    let indexedEdges: [IndexedEdge]

    init(calls: [ScheduledToolCall], indexedEdges: [IndexedEdge], waves: [[String]]) {
        self.calls = calls
        self.indexedEdges = indexedEdges
        self.waves = waves
    }

    public var edges: [ScheduleEdge] {
        indexedEdges.map { ScheduleEdge(from: calls[$0.from].id, to: calls[$0.to].id, reason: $0.reason) }
    }

    /// Rounds needed if every call ran one after another, which is what most agent loops do.
    public var sequentialRounds: Int {
        calls.count
    }

    /// Rounds needed with unlimited concurrency: the longest chain of constraints.
    public var criticalPathLength: Int {
        waves.count
    }

    public func wave(of callID: String) -> Int? {
        waves.firstIndex { $0.contains(callID) }
    }

    public func predecessors(of callID: String) -> [String] {
        edges.filter { $0.to == callID }.map(\.from)
    }
}
