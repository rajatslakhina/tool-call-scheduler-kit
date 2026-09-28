import XCTest
@testable import ToolCallSchedulerKit

final class ExecutionStateTests: XCTestCase {
    func testTakeReadyRespectsLimitAndOrder() throws {
        var state = ExecutionState(plan: try ToolCallPlanner.plan(
            [call("a", "pure"), call("b", "pure"), call("c", "pure")], catalog: fileCatalog))
        XCTAssertEqual(state.takeReady(limit: -1), [])
        XCTAssertEqual(state.takeReady(limit: 2), [0, 1])
        XCTAssertEqual(state.takeReady(limit: 5), [2])
        XCTAssertFalse(state.isFinished)
        for index in 0..<3 { state.complete(index, with: .succeeded("ok")) }
        XCTAssertTrue(state.isFinished)
    }

    func testFailurePropagatesOnlyAlongDependencies() throws {
        // a fails. b consumed a's result -> skipped. c consumed b's -> skipped, blamed on a.
        // d merely conflicts with a (same file) -> still runs once a is done.
        let plan = try ToolCallPlanner.plan([
            call("a", "write", "x"), call("b", "pure", dependsOn: ["a"]), call("c", "pure", dependsOn: ["b"]),
            call("d", "write", "x")
        ], catalog: fileCatalog)
        var state = ExecutionState(plan: plan)
        XCTAssertEqual(state.takeReady(limit: 4), [0])
        state.complete(0, with: .failed("boom"))
        XCTAssertEqual(state.outcomes[1], .skipped(blockedBy: "a"))
        XCTAssertEqual(state.outcomes[2], .skipped(blockedBy: "a"))
        XCTAssertEqual(state.takeReady(limit: 4), [3])
    }

    func testFirstFailureIsTheOneBlamed() throws {
        let plan = try ToolCallPlanner.plan([
            call("a", "pure"), call("b", "pure"), call("c", "pure", dependsOn: ["a", "b"])
        ], catalog: fileCatalog)
        var state = ExecutionState(plan: plan)
        _ = state.takeReady(limit: 2)
        state.complete(1, with: .failed("first"))
        XCTAssertNil(state.outcomes[2], "still waiting on a")
        state.complete(0, with: .failed("second"))
        XCTAssertEqual(state.outcomes[2], .skipped(blockedBy: "b"))
        XCTAssertTrue(state.isFinished)
    }

    func testSkippedCallReleasesConflictSuccessors() throws {
        let plan = try ToolCallPlanner.plan([
            call("a", "pure"), call("b", "write", "x", dependsOn: ["a"]), call("c", "write", "x")
        ], catalog: fileCatalog)
        var state = ExecutionState(plan: plan)
        XCTAssertEqual(state.takeReady(limit: 3), [0])
        state.complete(0, with: .failed("no"))
        XCTAssertEqual(state.outcomes[1], .skipped(blockedBy: "a"))
        XCTAssertEqual(state.takeReady(limit: 3), [2], "c only waited for b's write slot, not its result")
    }
}
