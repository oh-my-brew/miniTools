import Foundation

/// In-memory browsing continuity. No clipboard access or UI objects are retained.
struct ClipboardHistoryBrowsingState {
    struct Anchor {
        let order: [UUID]
        let index: Int
        let displacement: CGFloat

        init?(ids: [UUID], offset: CGFloat, stride: CGFloat) {
            guard !ids.isEmpty, stride > 0 else { return nil }
            order = ids
            index = min(max(Int(floor(max(0, offset) / stride)), 0), ids.count - 1)
            displacement = max(0, offset) - CGFloat(index) * stride
        }

        func offset(in ids: [UUID], stride: CGFloat) -> CGFloat {
            let survivors = Set(ids)
            guard order.contains(where: survivors.contains) else { return 0 }
            guard let id = Self.nearest(to: order[index], oldOrder: order, surviving: ids),
                  let newIndex = ids.firstIndex(of: id) else { return 0 }
            return max(0, CGFloat(newIndex) * stride + displacement)
        }

        static func nearest(to id: UUID?, oldOrder: [UUID], surviving: [UUID]) -> UUID? {
            if let id, surviving.contains(id) { return id }
            guard let id, let index = oldOrder.firstIndex(of: id) else { return surviving.first }
            let survivors = Set(surviving)
            for distance in 1...max(1, oldOrder.count) {
                // Prefer the next card, then the previous one, at equal distance.
                for candidate in [index + distance, index - distance] where oldOrder.indices.contains(candidate) {
                    if survivors.contains(oldOrder[candidate]) { return oldOrder[candidate] }
                }
            }
            return surviving.first
        }
    }

    private(set) var isPresented = false
    private var hasSavedContext = false
    private var used = false
    private var stackChanged = false
    private(set) var anchor: Anchor?
    private(set) var selectedID: UUID?
    private var order: [UUID] = []

    mutating func open() -> Bool {
        guard !isPresented else { return true }
        let resume = hasSavedContext && !used && !stackChanged
        isPresented = true
        used = false
        stackChanged = false
        return resume
    }

    mutating func close(ids: [UUID], selectedID: UUID?, offset: CGFloat, stride: CGFloat) {
        guard isPresented else { return }
        isPresented = false
        hasSavedContext = true
        order = ids
        self.selectedID = selectedID
        anchor = Anchor(ids: ids, offset: offset, stride: stride)
    }

    mutating func didUseItem() { used = true }
    mutating func didChangeStack() { stackChanged = true }

    func canRestoreContext(in ids: [UUID]) -> Bool {
        let survivors = Set(ids)
        return order.isEmpty || order.contains(where: survivors.contains)
    }

    func restoredSelection(in ids: [UUID]) -> UUID? {
        Anchor.nearest(to: selectedID, oldOrder: order, surviving: ids)
    }

    static func visibleOffset(index: Int, current: CGFloat, viewport: CGFloat,
                              cardWidth: CGFloat, stride: CGFloat, leadingInset: CGFloat) -> CGFloat {
        let left = CGFloat(index) * stride + leadingInset
        let right = left + cardWidth
        if left < current { return max(0, left - leadingInset) }
        if right > current + viewport { return max(0, right - viewport + leadingInset) }
        return current
    }
}

struct ClipboardHistoryScrollRequest: Equatable {
    let sequence: Int
    let offset: CGFloat
    let animated: Bool
}
