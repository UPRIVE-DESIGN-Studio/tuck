import CoreGraphics

/// Decides the next single step of automatic tucking. Pure, so it can be tested without a menu bar.
///
/// Rules, in order:
/// 1. A Hide item outside Tuck goes in; a Show item inside Tuck comes out.
/// 2. While anything on the visible side is behind the notch, tuck the least important Auto item.
/// 3. Once nothing is covered and there is room, bring back the most important item Tuck tucked
///    by itself.
enum AutoTuckPlanner {
    struct Candidate: Equatable {
        let key: ItemKey
        let width: CGFloat
        let placement: Placement
        let isOnScreen: Bool
        let mode: ItemStore.Mode
        let rank: Int
    }

    enum Step: Equatable {
        case tuck(ItemKey)
        case restore(ItemKey)
    }

    /// Room to keep free so an item whose width wobbles (live text) does not flip back and forth.
    static let margin: CGFloat = 12

    static func next(
        _ items: [Candidate], autoTucked: Set<ItemKey>, freeWidth: CGFloat, cooling: Set<ItemKey> = []
    ) -> Step? {
        if let stray = items.first(where: { $0.mode == .hide && $0.placement.isVisibleSide }) {
            return .tuck(stray.key)
        }
        if let stray = items.first(where: { $0.mode == .show && $0.placement == .hidden }) {
            return .restore(stray.key)
        }
        let covered = items.contains { $0.placement.isVisibleSide && !$0.isOnScreen }
        if covered {
            let tuckable = items.filter { $0.placement.isVisibleSide && $0.mode == .auto }
            return tuckable.max { $0.rank < $1.rank }.map { .tuck($0.key) }
        }
        let waiting = items
            .filter { $0.placement == .hidden && autoTucked.contains($0.key) && !cooling.contains($0.key) }
            .min { $0.rank < $1.rank }
        if let waiting, waiting.width + margin <= freeWidth {
            return .restore(waiting.key)
        }
        return nil
    }
}
