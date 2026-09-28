import ToolCallSchedulerKit

struct ToolFailure: Error, CustomStringConvertible {
    let description: String
}

let catalog = ToolEffectCatalog([
    "read_file": ToolEffectRule(reads: [ResourceSelector("file", instanceArgument: "path")]),
    "write_file": ToolEffectRule(writes: [ResourceSelector("file", instanceArgument: "path")]),
    "search_web": .pure,
    "get_weather": .pure,
    "fetch_invoice": ToolEffectRule(reads: [ResourceSelector("billing")]),
    "summarize": .pure,
    "send_email": ToolEffectRule(writes: [ResourceSelector("outbox")]),
    "append_audit": ToolEffectRule(writes: [ResourceSelector("audit")])
])

func describe(_ reason: EdgeReason) -> String {
    switch reason {
    case .dependency: return "declared dependency"
    case .resourceConflict(let keys): return "conflict on \(keys.joined(separator: ", "))"
    case .barrier: return "barrier (undeclared tool)"
    }
}

func describe(_ outcome: ToolCallOutcome) -> String {
    switch outcome {
    case .succeeded(let output): return "ok      \(output)"
    case .failed(let message): return "FAILED  \(message)"
    case .skipped(let blocker): return "SKIPPED blocked by \(blocker)"
    }
}

func printPlan(_ plan: SchedulePlan) {
    for (number, wave) in plan.waves.enumerated() {
        print("  wave \(number): \(wave.joined(separator: ", "))")
    }
    for edge in plan.edges {
        print("  \(edge.from) -> \(edge.to)  [\(describe(edge.reason))]")
    }
    print("  sequential rounds: \(plan.sequentialRounds), critical path: \(plan.criticalPathLength)")
}

func pad(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}

func printReport(_ report: ScheduleReport) {
    for record in report.records {
        let order = record.startOrder.map { "#\($0)" } ?? "--"
        print("  \(pad(record.call.id, 4)) \(pad(order, 3)) \(describe(record.outcome))")
    }
    let counts = "succeeded \(report.succeeded), failed \(report.failed), skipped \(report.skipped)"
    print("  \(counts); peak concurrency \(report.peakConcurrency)/\(report.maxConcurrency)")
}

func echoHandler(failing: Set<String> = []) -> ToolCallScheduler.Handler {
    { call in
        try await Task.sleep(nanoseconds: 20_000_000)
        if failing.contains(call.id) { throw ToolFailure(description: "\(call.toolName) returned HTTP 503") }
        let target = call.arguments["path"] ?? call.arguments["city"] ?? call.arguments["query"] ?? ""
        return "\(call.toolName)(\(target))"
    }
}

let codingTurn = [
    ScheduledToolCall(id: "c1", toolName: "read_file", arguments: ["path": "Package.swift"]),
    ScheduledToolCall(id: "c2", toolName: "read_file", arguments: ["path": "README.md"]),
    ScheduledToolCall(id: "c3", toolName: "write_file", arguments: ["path": "Package.swift"]),
    ScheduledToolCall(id: "c4", toolName: "search_web", arguments: ["query": "swift 6.2 release notes"]),
    ScheduledToolCall(id: "c5", toolName: "write_file", arguments: ["path": "Package.swift"]),
    ScheduledToolCall(id: "c6", toolName: "get_weather", arguments: ["city": "Delhi"])
]

func scenarioCodingTurn() async throws {
    print("1. One coding-agent turn, six calls")
    let scheduler = try ToolCallScheduler(catalog: catalog, maxConcurrency: 3)
    printPlan(try scheduler.plan(codingTurn))
    print("  executing with maxConcurrency 3:")
    printReport(try await scheduler.execute(codingTurn, handler: echoHandler()))
}

func scenarioFailure() async throws {
    print("\n2. A failure only takes down calls that consumed its result")
    let calls = [
        ScheduledToolCall(id: "f1", toolName: "fetch_invoice", arguments: ["query": "INV-2291"]),
        ScheduledToolCall(id: "f2", toolName: "summarize", dependsOn: ["f1"]),
        ScheduledToolCall(id: "f3", toolName: "send_email", dependsOn: ["f2"]),
        ScheduledToolCall(id: "f4", toolName: "append_audit"),
        ScheduledToolCall(id: "f5", toolName: "append_audit"),
        ScheduledToolCall(id: "f6", toolName: "get_weather", arguments: ["city": "Pune"])
    ]
    let scheduler = try ToolCallScheduler(catalog: catalog, maxConcurrency: 4)
    printPlan(try scheduler.plan(calls))
    printReport(try await scheduler.execute(calls, handler: echoHandler(failing: ["f1", "f4"])))
}

func scenarioBarrier() async throws {
    print("\n3. An undeclared tool runs alone, in emission order")
    let calls = [
        ScheduledToolCall(id: "b1", toolName: "get_weather", arguments: ["city": "Goa"]),
        ScheduledToolCall(id: "b2", toolName: "run_shell", arguments: ["query": "rm -rf build"]),
        ScheduledToolCall(id: "b3", toolName: "get_weather", arguments: ["city": "Leh"])
    ]
    let scheduler = try ToolCallScheduler(catalog: catalog)
    print("  run_shell declared: \(catalog.isDeclared("run_shell"))")
    printPlan(try scheduler.plan(calls))
}

func scenarioMalformed() throws {
    print("\n4. Malformed batches are refused before anything runs")
    let scheduler = try ToolCallScheduler(catalog: catalog)
    let batches: [(String, [ScheduledToolCall])] = [
        ("duplicate id", [ScheduledToolCall(id: "x", toolName: "search_web"),
                          ScheduledToolCall(id: "x", toolName: "search_web")]),
        ("unknown dependency", [ScheduledToolCall(id: "y", toolName: "summarize", dependsOn: ["ghost"])]),
        ("cycle", [ScheduledToolCall(id: "p", toolName: "summarize", dependsOn: ["q"]),
                   ScheduledToolCall(id: "q", toolName: "summarize", dependsOn: ["p"])])
    ]
    for (label, batch) in batches {
        do {
            _ = try scheduler.plan(batch)
            print("  \(label): planned (unexpected)")
        } catch {
            print("  \(label): \(error)")
        }
    }
    do {
        _ = try ToolCallScheduler(catalog: catalog, maxConcurrency: 0)
    } catch {
        print("  maxConcurrency 0: \(error)")
    }
}

@main
struct ToolCallSchedulerDemo {
    static func main() async throws {
        print("ToolCallSchedulerKit demo\n")
        try await scenarioCodingTurn()
        try await scenarioFailure()
        try await scenarioBarrier()
        try scenarioMalformed()
    }
}
