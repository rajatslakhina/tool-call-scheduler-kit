/// A thing a tool call touches: a resource family, optionally narrowed to one instance.
///
/// `file` with no instance means "every file". `file` with instance `notes.md` means one file.
/// Two keys overlap when they name the same resource and at least one of them is unnarrowed, or
/// both name the same instance. Unnarrowed keys are the conservative case: if a call's arguments
/// don't say which file it writes, it is treated as writing all of them.
public struct ResourceKey: Sendable, Hashable, CustomStringConvertible {
    public let resource: String
    public let instance: String?

    public init(_ resource: String, instance: String? = nil) {
        self.resource = resource
        self.instance = instance
    }

    public func overlaps(_ other: ResourceKey) -> Bool {
        guard resource == other.resource else { return false }
        guard let mine = instance, let theirs = other.instance else { return true }
        return mine == theirs
    }

    public var description: String {
        "\(resource):\(instance ?? "*")"
    }
}

/// What one call reads and writes. A barrier call conflicts with every other call in the batch.
public struct ToolEffects: Sendable, Equatable {
    public let reads: Set<ResourceKey>
    public let writes: Set<ResourceKey>
    public let isBarrier: Bool

    public init(reads: Set<ResourceKey> = [], writes: Set<ResourceKey> = [], isBarrier: Bool = false) {
        self.reads = reads
        self.writes = writes
        self.isBarrier = isBarrier
    }

    /// No declared effects. Safe to run alongside anything that isn't a barrier.
    public static let pure = ToolEffects()
    /// Unknown effects. Runs alone, in emission order relative to every other call.
    public static let barrier = ToolEffects(isBarrier: true)

    /// Read/write, write/read and write/write overlaps conflict. Read/read never does.
    public func conflicts(with other: ToolEffects) -> Bool {
        if isBarrier || other.isBarrier { return true }
        return Self.anyOverlap(writes, other.reads)
            || Self.anyOverlap(writes, other.writes)
            || Self.anyOverlap(reads, other.writes)
    }

    private static func anyOverlap(_ lhs: Set<ResourceKey>, _ rhs: Set<ResourceKey>) -> Bool {
        lhs.contains { key in rhs.contains { key.overlaps($0) } }
    }
}
