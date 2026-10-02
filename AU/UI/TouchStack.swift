import CoreGraphics

/// The fingers on the scene, oldest first, and what the pad should do as they
/// come and go. The scene plays like a mono keyboard with last-note priority:
/// the newest finger sings, lifting it hands back to the finger that is still
/// down — from where that finger is now — and the note ends with the last one.
///
/// Generic over the touch's identity so it can be tested without `UITouch`
/// (which has no public initializer).
struct TouchStack<ID: Hashable> {
    enum Action: Equatable {
        case begin(CGPoint)   // the first finger: start a note here
        case move(CGPoint)    // retarget the sounding note here
        case end              // the last finger is up
    }

    private var order: [ID] = []
    private var points: [ID: CGPoint] = [:]

    var isEmpty: Bool { order.isEmpty }

    mutating func press(_ id: ID, at p: CGPoint) -> Action {
        let wasEmpty = order.isEmpty
        order.removeAll { $0 == id }
        order.append(id)
        points[id] = p
        return wasEmpty ? .begin(p) : .move(p)
    }

    /// Only the newest finger plays; the others are tracked silently so a
    /// hand-back lands where they are.
    mutating func move(_ id: ID, to p: CGPoint) -> Action? {
        guard points[id] != nil else { return nil }
        points[id] = p
        return order.last == id ? .move(p) : nil
    }

    mutating func lift(_ id: ID) -> Action? {
        guard let i = order.firstIndex(of: id) else { return nil }
        let wasTop = i == order.count - 1
        order.remove(at: i)
        points[id] = nil
        guard wasTop else { return nil }
        guard let next = order.last, let p = points[next] else { return .end }
        return .move(p)
    }
}
