import XCTest
@testable import ToolCallSchedulerKit

final class EffectsTests: XCTestCase {
    func testResourceKeyOverlap() {
        let anyFile = ResourceKey("file")
        let notes = ResourceKey("file", instance: "notes.md")
        let todo = ResourceKey("file", instance: "todo.md")
        XCTAssertTrue(anyFile.overlaps(notes))
        XCTAssertTrue(notes.overlaps(anyFile))
        XCTAssertTrue(notes.overlaps(notes))
        XCTAssertFalse(notes.overlaps(todo))
        XCTAssertFalse(notes.overlaps(ResourceKey("db", instance: "notes.md")))
    }

    func testResourceKeyDescription() {
        XCTAssertEqual(ResourceKey("file").description, "file:*")
        XCTAssertEqual(ResourceKey("file", instance: "a").description, "file:a")
    }

    func testConflictMatrix() {
        let readA = ToolEffects(reads: [ResourceKey("file", instance: "a")])
        let writeA = ToolEffects(writes: [ResourceKey("file", instance: "a")])
        let writeB = ToolEffects(writes: [ResourceKey("file", instance: "b")])
        XCTAssertFalse(readA.conflicts(with: readA), "read/read never conflicts")
        XCTAssertTrue(readA.conflicts(with: writeA))
        XCTAssertTrue(writeA.conflicts(with: readA))
        XCTAssertTrue(writeA.conflicts(with: writeA))
        XCTAssertFalse(writeA.conflicts(with: writeB))
        XCTAssertFalse(ToolEffects.pure.conflicts(with: writeA))
        XCTAssertTrue(ToolEffects.barrier.conflicts(with: .pure))
        XCTAssertTrue(ToolEffects.pure.conflicts(with: .barrier))
    }

    func testCatalogTreatsUndeclaredToolsAsBarriers() {
        var catalog = ToolEffectCatalog()
        let call = ScheduledToolCall(id: "1", toolName: "mystery")
        XCTAssertFalse(catalog.isDeclared("mystery"))
        XCTAssertEqual(catalog.effects(of: call), .barrier)
        catalog.register("mystery", .pure)
        XCTAssertTrue(catalog.isDeclared("mystery"))
        XCTAssertEqual(catalog.effects(of: call), .pure)
        catalog.register("mystery", .barrier)
        XCTAssertEqual(catalog.effects(of: call), .barrier)
    }

    func testSelectorNarrowsOnlyWhenArgumentPresent() {
        let catalog = ToolEffectCatalog([
            "write": ToolEffectRule(reads: [ResourceSelector("index")],
                                    writes: [ResourceSelector("file", instanceArgument: "path")])
        ])
        let narrowed = catalog.effects(of: ScheduledToolCall(id: "1", toolName: "write", arguments: ["path": "a"]))
        XCTAssertEqual(narrowed.writes, [ResourceKey("file", instance: "a")])
        XCTAssertEqual(narrowed.reads, [ResourceKey("index")])
        let unnarrowed = catalog.effects(of: ScheduledToolCall(id: "2", toolName: "write"))
        XCTAssertEqual(unnarrowed.writes, [ResourceKey("file")])
        XCTAssertFalse(unnarrowed.isBarrier)
    }

    func testOutcomeIsSuccess() {
        XCTAssertTrue(ToolCallOutcome.succeeded("x").isSuccess)
        XCTAssertFalse(ToolCallOutcome.failed("x").isSuccess)
        XCTAssertFalse(ToolCallOutcome.skipped(blockedBy: "x").isSuccess)
    }
}
