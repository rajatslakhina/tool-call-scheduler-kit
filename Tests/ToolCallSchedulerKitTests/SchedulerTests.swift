import XCTest
@testable import ToolCallSchedulerKit

private struct Boom: Error, CustomStringConvertible {
    var description: String { "boom" }
}

/// Records how many calls touch each path at the same moment.
private actor Overlap {
    private var inFlight: [String: Int] = [:]
    private(set) var worst: [String: Int] = [:]
    private var total = 0
    private(set) var worstTotal = 0

    func enter(_ path: String) {
        inFlight[path, default: 0] += 1
        worst[path] = max(worst[path, default: 0], inFlight[path, default: 0])
        total += 1
        worstTotal = max(worstTotal, total)
    }

    func leave(_ path: String) {
        inFlight[path, default: 0] -= 1
        total -= 1
    }
}

final class SchedulerTests: XCTestCase {
    func testRejectsInvalidConcurrency() {
        XCTAssertThrowsError(try ToolCallScheduler(catalog: fileCatalog, maxConcurrency: 0)) {
            XCTAssertEqual($0 as? SchedulingError, .invalidConcurrency(0))
        }
    }

    func testWritesToOneFileNeverOverlapAndResultsKeepEmissionOrder() async throws {
        let overlap = Overlap()
        var batch: [ScheduledToolCall] = []
        for index in 0..<12 {
            let path = ["a", "b", "c"][index % 3]
            batch.append(call("w\(index)", index % 2 == 0 ? "write" : "read", path))
        }
        let scheduler = try ToolCallScheduler(catalog: fileCatalog, maxConcurrency: 6)
        let report = try await scheduler.execute(batch) { call in
            let path = call.arguments["path"] ?? ""
            let key = call.toolName == "write" ? "w:\(path)" : "r:\(path)"
            await overlap.enter(key)
            try await Task.sleep(nanoseconds: 2_000_000)
            await overlap.leave(key)
            return call.id
        }
        XCTAssertEqual(report.records.map(\.call.id), batch.map(\.id))
        XCTAssertEqual(report.records.map(\.outcome), batch.map { .succeeded($0.id) })
        let worst = await overlap.worst
        for path in ["a", "b", "c"] { XCTAssertEqual(worst["w:\(path)"], 1) }
        let worstTotal = await overlap.worstTotal
        XCTAssertLessThanOrEqual(worstTotal, 6)
        XCTAssertLessThanOrEqual(report.peakConcurrency, 6)
        XCTAssertEqual(report.succeeded, 12)
    }

    func testConcurrencyOneRunsInEmissionOrder() async throws {
        let scheduler = try ToolCallScheduler(catalog: fileCatalog, maxConcurrency: 1)
        let report = try await scheduler.execute([call("a", "pure"), call("b", "pure"), call("c", "pure")]) { $0.id }
        XCTAssertEqual(report.records.map(\.startOrder), [0, 1, 2])
        XCTAssertEqual(report.peakConcurrency, 1)
        XCTAssertEqual(report.maxConcurrency, 1)
    }

    func testIndependentCallsRunTogether() async throws {
        let scheduler = try ToolCallScheduler(catalog: fileCatalog)
        let report = try await scheduler.execute([call("a", "pure"), call("b", "pure"), call("c", "pure")]) { call in
            try await Task.sleep(nanoseconds: 5_000_000)
            return call.id
        }
        XCTAssertEqual(report.peakConcurrency, 3)
        XCTAssertEqual(scheduler.maxConcurrency, 4)
    }

    func testFailureSkipsDependentsAndCounts() async throws {
        let scheduler = try ToolCallScheduler(catalog: fileCatalog, maxConcurrency: 2)
        let batch = [call("a", "pure"), call("b", "pure", dependsOn: ["a"]), call("c", "pure")]
        let report = try await scheduler.execute(batch) { call in
            if call.id == "a" { throw Boom() }
            return "done"
        }
        XCTAssertEqual(report.record(for: "a")?.outcome, .failed("boom"))
        XCTAssertEqual(report.record(for: "b")?.outcome, .skipped(blockedBy: "a"))
        XCTAssertNil(report.record(for: "b")?.startOrder)
        XCTAssertEqual(report.record(for: "c")?.outcome, .succeeded("done"))
        XCTAssertNil(report.record(for: "zzz"))
        XCTAssertEqual([report.succeeded, report.failed, report.skipped], [1, 1, 1])

        let batches = await scheduler.batchesExecuted
        let started = await scheduler.callsStarted
        let skipped = await scheduler.callsSkipped
        XCTAssertEqual([batches, started, skipped], [1, 2, 1])
    }

    func testMalformedBatchRunsNothing() async throws {
        let scheduler = try ToolCallScheduler(catalog: fileCatalog)
        do {
            _ = try await scheduler.execute([call("a", "pure"), call("a", "pure")]) { _ in
                XCTFail("must not run")
                return ""
            }
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? SchedulingError, .duplicateCallID("a"))
        }
        let batches = await scheduler.batchesExecuted
        XCTAssertEqual(batches, 0)
    }

    func testEmptyBatch() async throws {
        let scheduler = try ToolCallScheduler(catalog: fileCatalog)
        let report = try await scheduler.execute([]) { $0.id }
        XCTAssertEqual(report.records, [])
        XCTAssertEqual(report.peakConcurrency, 0)
    }

    func testPlanIsExposedWithoutRunning() throws {
        let scheduler = try ToolCallScheduler(catalog: fileCatalog)
        XCTAssertEqual(try scheduler.plan([call("a", "write", "x"), call("b", "write", "x")]).waves, [["a"], ["b"]])
        XCTAssertTrue(scheduler.catalog.isDeclared("write"))
    }
}
