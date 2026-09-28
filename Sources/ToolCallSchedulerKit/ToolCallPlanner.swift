/// Turns a batch of calls plus an effect catalog into a `SchedulePlan`. Pure and synchronous, so
/// a host can inspect a plan without running anything.
public enum ToolCallPlanner {
    private struct Pair: Hashable {
        let from: Int
        let to: Int
    }

    public static func plan(_ calls: [ScheduledToolCall], catalog: ToolEffectCatalog) throws -> SchedulePlan {
        var indexByID: [String: Int] = [:]
        for (index, call) in calls.enumerated() where indexByID.updateValue(index, forKey: call.id) != nil {
            throw SchedulingError.duplicateCallID(call.id)
        }

        var declared = Set<Pair>()
        var edges: [IndexedEdge] = []
        for (index, call) in calls.enumerated() {
            for dependency in call.dependsOn {
                guard let from = indexByID[dependency] else {
                    throw SchedulingError.unknownDependency(callID: call.id, dependsOn: dependency)
                }
                if declared.insert(Pair(from: from, to: index)).inserted {
                    edges.append(IndexedEdge(from: from, to: index, reason: .dependency))
                }
            }
        }

        let effects = calls.map(catalog.effects(of:))
        for later in calls.indices {
            for earlier in 0..<later {
                let pairIsDeclared = declared.contains(Pair(from: earlier, to: later))
                    || declared.contains(Pair(from: later, to: earlier))
                guard !pairIsDeclared, let reason = conflictReason(effects[earlier], effects[later]) else { continue }
                edges.append(IndexedEdge(from: earlier, to: later, reason: reason))
            }
        }

        let waves = try layer(calls, edges: edges)
        return SchedulePlan(calls: calls, indexedEdges: edges, waves: waves)
    }

    static func conflictReason(_ earlier: ToolEffects, _ later: ToolEffects) -> EdgeReason? {
        guard earlier.conflicts(with: later) else { return nil }
        if earlier.isBarrier || later.isBarrier { return .barrier }
        let written = earlier.writes.filter { key in
            later.reads.contains { key.overlaps($0) } || later.writes.contains { key.overlaps($0) }
        }
        let readThenWritten = earlier.reads.filter { key in later.writes.contains { key.overlaps($0) } }
        return .resourceConflict(Set((written.union(readThenWritten)).map(\.description)).sorted())
    }

    private static func layer(_ calls: [ScheduledToolCall], edges: [IndexedEdge]) throws -> [[String]] {
        var indegree = [Int](repeating: 0, count: calls.count)
        var successors = [[Int]](repeating: [], count: calls.count)
        for edge in edges {
            indegree[edge.to] += 1
            successors[edge.from].append(edge.to)
        }

        var level = [Int](repeating: 0, count: calls.count)
        var queue = calls.indices.filter { indegree[$0] == 0 }
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for next in successors[node] {
                level[next] = max(level[next], level[node] + 1)
                indegree[next] -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }

        guard queue.count == calls.count else {
            let stuck = calls.indices.filter { indegree[$0] > 0 }.map { calls[$0].id }
            throw SchedulingError.dependencyCycle(involving: stuck)
        }

        var waves = [[String]](repeating: [], count: (level.max() ?? -1) + 1)
        for (index, call) in calls.enumerated() {
            waves[level[index]].append(call.id)
        }
        return waves
    }
}
