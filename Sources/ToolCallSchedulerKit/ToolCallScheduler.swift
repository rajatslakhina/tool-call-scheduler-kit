/// Runs one turn's tool calls as concurrently as their declared effects allow.
///
/// Providers happily emit several tool calls in one turn and most clients either run them one at
/// a time (slow) or all at once (wrong when two of them write the same thing). The scheduler sits
/// between the two: it plans the batch with `ToolCallPlanner`, starts every call whose
/// predecessors are done as soon as a concurrency slot is free, and returns results in emission
/// order so they can go straight back to the provider.
public actor ToolCallScheduler {
    public typealias Handler = @Sendable (ScheduledToolCall) async throws -> String

    public nonisolated let catalog: ToolEffectCatalog
    public nonisolated let maxConcurrency: Int
    public private(set) var batchesExecuted = 0
    public private(set) var callsStarted = 0
    public private(set) var callsSkipped = 0

    public init(catalog: ToolEffectCatalog, maxConcurrency: Int = 4) throws {
        guard maxConcurrency >= 1 else { throw SchedulingError.invalidConcurrency(maxConcurrency) }
        self.catalog = catalog
        self.maxConcurrency = maxConcurrency
    }

    public nonisolated func plan(_ calls: [ScheduledToolCall]) throws -> SchedulePlan {
        try ToolCallPlanner.plan(calls, catalog: catalog)
    }

    public func execute(_ calls: [ScheduledToolCall], handler: @escaping Handler) async throws -> ScheduleReport {
        let plan = try plan(calls)
        var state = ExecutionState(plan: plan)
        var startOrders = [Int?](repeating: nil, count: calls.count)
        var running = 0
        var peak = 0
        var started = 0
        let limit = maxConcurrency

        await withTaskGroup(of: (Int, ToolCallOutcome).self) { group in
            while true {
                for index in state.takeReady(limit: limit - running) {
                    let call = plan.calls[index]
                    startOrders[index] = started
                    started += 1
                    running += 1
                    peak = max(peak, running)
                    group.addTask {
                        do {
                            return (index, .succeeded(try await handler(call)))
                        } catch {
                            return (index, .failed(String(describing: error)))
                        }
                    }
                }
                guard let (index, outcome) = await group.next() else { break }
                running -= 1
                state.complete(index, with: outcome)
            }
        }

        let records = state.outcomes.enumerated().compactMap { index, outcome in
            outcome.map { ToolCallRecord(call: plan.calls[index], outcome: $0, startOrder: startOrders[index]) }
        }
        batchesExecuted += 1
        callsStarted += started
        callsSkipped += calls.count - started
        return ScheduleReport(plan: plan, records: records, maxConcurrency: limit, peakConcurrency: peak)
    }
}
