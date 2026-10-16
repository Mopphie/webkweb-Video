import Foundation

struct QueueEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var address: String
}
enum QueueRepeat: String, CaseIterable, Codable, Identifiable {
    case none, one, all
    var id: String { rawValue }
    var title: String { self == .none ? "Aus" : self == .one ? "Ein Titel" : "Alle" }
}

/// Order contains a whole permutation, rather than repeatedly choosing a random
/// neighbour. IDs keep remove/reorder operations independent of array indices.
struct PlaybackQueue: Codable, Equatable {
    var entries: [QueueEntry] = []
    private(set) var order: [UUID] = []
    private(set) var currentID: UUID?
    private(set) var previousIDs: [UUID] = []
    var repeatMode = QueueRepeat.none
    private(set) var shuffled = false
    var current: QueueEntry? { entries.first { $0.id == currentID } }
    var canNext: Bool {
        guard !entries.isEmpty else { return false }
        guard let index = order.firstIndex(where: { $0 == currentID }) else { return true }
        return index + 1 < order.count || repeatMode == .all
    }
    var canPrevious: Bool { previousIDs.contains { id in entries.contains { $0.id == id } } }
    mutating func append(_ entry: QueueEntry) {
        guard entries.count < 10_000, LibraryAddress.clean(entry.address) != nil,
              !entries.contains(where: { $0.id == entry.id || $0.address == entry.address }) else { return }
        entries.append(entry)
        if shuffled {
            let lower = order.firstIndex(where: { $0 == currentID }).map { $0 + 1 } ?? 0
            order.insert(entry.id, at: Int.random(in: lower...order.count))
        } else { order.append(entry.id) }
    }
    mutating func replace(_ values: [QueueEntry]) {
        entries = values; currentID = nil; previousIDs = []; rebuildOrder()
    }
    mutating func setShuffle(_ value: Bool) { shuffled = value; rebuildOrder() }
    private mutating func rebuildOrder() {
        order = entries.map(\.id)
        if shuffled { order.shuffle() } // Standard-library Fisher–Yates.
        if shuffled, let currentID, let index = order.firstIndex(of: currentID) {
            order.remove(at: index); order.insert(currentID, at: 0)
        }
    }
    mutating func select(_ id: UUID) -> QueueEntry? {
        guard entries.contains(where: { $0.id == id }) else { return nil }
        if let old = currentID, old != id { previousIDs.append(old); trimHistory() }
        currentID = id; return current
    }
    mutating func next(automatic: Bool = false) -> QueueEntry? {
        guard !entries.isEmpty else { return nil }
        if automatic, repeatMode == .one, let current { return current }
        guard let index = order.firstIndex(where: { $0 == currentID }) else { return order.first.flatMap { select($0) } }
        if index + 1 < order.count { return select(order[index + 1]) }
        guard repeatMode == .all else { return nil }
        let old = currentID
        order = entries.map(\.id)
        if shuffled {
            order.shuffle()
            if order.count > 1, order.first == old { order.swapAt(0, 1) }
        }
        return order.first.flatMap { select($0) }
    }
    mutating func previous() -> QueueEntry? {
        while let id = previousIDs.popLast() {
            if entries.contains(where: { $0.id == id }) { currentID = id; return current }
        }
        return nil
    }
    mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }; order.removeAll { $0 == id }; previousIDs.removeAll { $0 == id }
        if currentID == id { currentID = nil }
    }
    mutating func move(from offsets: IndexSet, to destination: Int) {
        // Foundation-only implementation so this algorithm needs no UI layer.
        let offsets = IndexSet(offsets.filter { entries.indices.contains($0) })
        let moving = offsets.sorted().map { entries[$0] }
        for index in offsets.sorted(by: >) { entries.remove(at: index) }
        let target = min(entries.count, max(0, destination - offsets.filter { $0 < destination }.count))
        entries.insert(contentsOf: moving, at: target)
        if !shuffled { order = entries.map(\.id) }
    }
    mutating func validate() {
        var ids = Set<UUID>()
        entries = entries.filter { ids.insert($0.id).inserted && LibraryAddress.clean($0.address) != nil }
        let valid = Set(entries.map(\.id))
        var ordered = Set<UUID>()
        order = order.filter { valid.contains($0) && ordered.insert($0).inserted }
        order += entries.map(\.id).filter { !ordered.contains($0) }
        previousIDs = previousIDs.filter { valid.contains($0) }
        if let currentID, !valid.contains(currentID) { self.currentID = nil }
    }
    private mutating func trimHistory() { if previousIDs.count > 500 { previousIDs.removeFirst(previousIDs.count - 500) } }
}

struct MediaTrack: Identifiable, Equatable {
    let id: Int
    let title: String
    let selected: Bool
    init?(_ value: [String: Any]) {
        guard let id = value["id"] as? Int, id >= 0, id < 100 else { return nil }
        self.id = id; title = String((value["title"] as? String ?? "Spur \(id + 1)").prefix(80)); selected = value["selected"] as? Bool ?? false
    }
}
