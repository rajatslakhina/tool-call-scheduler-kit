import XCTest
@testable import ToolCallSchedulerKit

let fileCatalog = ToolEffectCatalog([
    "read": ToolEffectRule(reads: [ResourceSelector("file", instanceArgument: "path")]),
    "write": ToolEffectRule(writes: [ResourceSelector("file", instanceArgument: "path")]),
    "pure": .pure
])

func call(_ id: String, _ tool: String, _ path: String? = nil, dependsOn: [String] = []) -> ScheduledToolCall {
    ScheduledToolCall(id: id, toolName: tool, arguments: path.map { ["path": $0] } ?? [:], dependsOn: dependsOn)
}

final class PlannerTests: XCTestCase {
    func testEmptyBatch() throws {
        let plan = try ToolCallPlanner.plan([], catalog: fileCatalog)
        XCTAssertEqual(plan.waves, [])
        XCTAssertEqual(plan.criticalPathLength, 0)
        XCTAssertEqual(plan.sequentialRounds, 0)
        XCTAssertEqual(plan.edges, [])
    }

    func testIndependentCallsShareOneWave() throws {
        let plan = try ToolCallPlanner.plan([call("a", "read", "x"), call("b", "read", "x"), call("c", "pure")],
                                            catalog: fileCatalog)
        XCTAssertEqual(plan.waves, [["a", "b", "c"]])
        XCTAssertEqual(plan.edges, [])
    }

    func testConflictsKeepEmissionOrder() throws {
        let plan = try ToolCallPlanner.plan(
            [call("r", "read", "x"), call("w", "write", "x"), call("o", "write", "y"), call("w2", "write", "x")],
            catalog: fileCatalog)
        XCTAssertEqual(plan.waves, [["r", "o"], ["w"], ["w2"]])
        XCTAssertEqual(plan.edges, [
            ScheduleEdge(from: "r", to: "w", reason: .resourceConflict(["file:x"])),
            ScheduleEdge(from: "r", to: "w2", reason: .resourceConflict(["file:x"])),
            ScheduleEdge(from: "w", to: "w2", reason: .resourceConflict(["file:x"]))
        ])
        XCTAssertEqual(plan.wave(of: "w2"), 2)
        XCTAssertNil(plan.wave(of: "missing"))
        XCTAssertEqual(plan.predecessors(of: "w2"), ["r", "w"])
    }

    func testWriteThenReadConflictNamesWrittenKey() throws {
        let plan = try ToolCallPlanner.plan([call("w", "write"), call("r", "read", "x")], catalog: fileCatalog)
        XCTAssertEqual(plan.edges.first?.reason, .resourceConflict(["file:*"]))
    }

    func testConflictReasonIsNilWithoutOverlap() {
        XCTAssertNil(ToolCallPlanner.conflictReason(.pure, .pure))
        XCTAssertEqual(ToolCallPlanner.conflictReason(.barrier, .pure), .barrier)
    }

    func testBarrierSerializesAgainstEverything() throws {
        let plan = try ToolCallPlanner.plan([call("a", "pure"), call("b", "unknown"), call("c", "pure")],
                                            catalog: fileCatalog)
        XCTAssertEqual(plan.waves, [["a"], ["b"], ["c"]])
        XCTAssertEqual(plan.edges.map(\.reason), [.barrier, .barrier])
    }

    func testDeclaredDependencyReplacesConflictEdgeInEitherDirection() throws {
        // "a" is emitted first but declares it needs "b". Without the override the conflict edge
        // a -> b and the dependency b -> a would form a cycle.
        let plan = try ToolCallPlanner.plan([call("a", "write", "x", dependsOn: ["b", "b"]), call("b", "read", "x")],
                                            catalog: fileCatalog)
        XCTAssertEqual(plan.edges, [ScheduleEdge(from: "b", to: "a", reason: .dependency)])
        XCTAssertEqual(plan.waves, [["b"], ["a"]])
    }

    func testDuplicateID() {
        XCTAssertThrowsError(try ToolCallPlanner.plan([call("a", "pure"), call("a", "pure")], catalog: fileCatalog)) {
            XCTAssertEqual($0 as? SchedulingError, .duplicateCallID("a"))
        }
    }

    func testUnknownDependency() {
        XCTAssertThrowsError(try ToolCallPlanner.plan([call("a", "pure", dependsOn: ["z"])], catalog: fileCatalog)) {
            XCTAssertEqual($0 as? SchedulingError, .unknownDependency(callID: "a", dependsOn: "z"))
        }
    }

    func testCycleReportsCallsInAndBehindIt() {
        let batch = [call("free", "pure"), call("p", "pure", dependsOn: ["q"]), call("q", "pure", dependsOn: ["p"]),
                     call("tail", "pure", dependsOn: ["q"])]
        XCTAssertThrowsError(try ToolCallPlanner.plan(batch, catalog: fileCatalog)) {
            XCTAssertEqual($0 as? SchedulingError, .dependencyCycle(involving: ["p", "q", "tail"]))
        }
    }

    func testSelfDependencyIsACycle() {
        XCTAssertThrowsError(try ToolCallPlanner.plan([call("s", "pure", dependsOn: ["s"])], catalog: fileCatalog)) {
            XCTAssertEqual($0 as? SchedulingError, .dependencyCycle(involving: ["s"]))
        }
    }
}
