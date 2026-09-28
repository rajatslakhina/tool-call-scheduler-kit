/// The bookkeeping half of execution, kept apart from the task group so every branch of it can be
/// tested without concurrency.
struct ExecutionState {
    private struct Successor {
        let index: Int
        let propagatesFailure: Bool
    }

    private let calls: [ScheduledToolCall]
    private let successors: [[Successor]]
    private var pending: [Int]
    private var blockedBy: [String?]
    private var ready: [Int]
    private(set) var outcomes: [ToolCallOutcome?]

    init(plan: SchedulePlan) {
        calls = plan.calls
        var successors = [[Successor]](repeating: [], count: plan.calls.count)
        var pending = [Int](repeating: 0, count: plan.calls.count)
        for edge in plan.indexedEdges {
            successors[edge.from].append(Successor(index: edge.to, propagatesFailure: edge.reason.propagatesFailure))
            pending[edge.to] += 1
        }
        self.successors = successors
        self.pending = pending
        blockedBy = [String?](repeating: nil, count: plan.calls.count)
        outcomes = [ToolCallOutcome?](repeating: nil, count: plan.calls.count)
        ready = plan.calls.indices.filter { pending[$0] == 0 }
    }

    var isFinished: Bool {
        !outcomes.contains(nil)
    }

    /// Removes up to `limit` ready calls, in emission order.
    mutating func takeReady(limit: Int) -> [Int] {
        let taken = Array(ready.prefix(max(limit, 0)))
        ready.removeFirst(taken.count)
        return taken
    }

    mutating func complete(_ index: Int, with outcome: ToolCallOutcome) {
        outcomes[index] = outcome
        let rootFailure: String? = if case .failed = outcome { calls[index].id } else { nil }
        release(successorsOf: index, rootFailure: rootFailure)
    }

    private mutating func release(successorsOf index: Int, rootFailure: String?) {
        for successor in successors[index] {
            if successor.propagatesFailure, blockedBy[successor.index] == nil {
                blockedBy[successor.index] = rootFailure
            }
            pending[successor.index] -= 1
            guard pending[successor.index] == 0 else { continue }
            if let blocker = blockedBy[successor.index] {
                outcomes[successor.index] = .skipped(blockedBy: blocker)
                release(successorsOf: successor.index, rootFailure: blocker)
            } else {
                ready.append(successor.index)
            }
        }
    }
}
