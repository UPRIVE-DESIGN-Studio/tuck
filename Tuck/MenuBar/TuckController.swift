import AppKit

/// Hides, shows and opens menu bar items. Operations run one at a time, in order, because each
/// one changes the layout the next one measures.
final class TuckController {
    let controls = ControlItems()
    lazy var scanner = ItemScanner(controls: controls)
    let mover = ItemMover()

    private var tail: Task<Void, Never>?
    private var tempShown: TempShown?
    private var watcher: Task<Void, Never>?

    /// An item moved next to the dot so it could be clicked, and where it goes back to.
    private struct TempShown {
        let windowID: CGWindowID
        let returnTo: ItemMover.Destination
        let windowsBefore: Set<CGWindowID>
        let started: ContinuousClock.Instant
    }

    func enqueue(_ work: @escaping () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await work()
        }
    }

    // MARK: Hide / show

    /// Moves an item into the hidden section, left of the separator.
    func hide(_ windowID: CGWindowID) async {
        await prepareSeparatorForMoves()
        guard let separator = scanner.scan(resolveOwners: false).separator else {
            Log.error("hide: separator window not found")
            return
        }
        _ = await mover.move(windowID, to: .leftOf(separator.windowID), landed: pushedOffScreen)
        await settleSeparator()
    }

    /// With the separator collapsed, anything that lands in the hidden section ends up past the
    /// left edge of every screen.
    private func pushedOffScreen(_ frame: CGRect) -> Bool {
        controls.separatorState == .collapsed && frame.maxX <= 0
    }

    /// Brings an item back into the menu bar, just left of the dot.
    func show(_ windowID: CGWindowID) async {
        guard let destination = nextToDot(moving: windowID) else {
            Log.error("show: no place next to the dot")
            return
        }
        _ = await mover.move(windowID, to: destination)
        await settleSeparator()
    }

    /// "Just left of the dot", expressed against the item already there. Events must never be
    /// addressed to the dot itself: macOS would deliver them to Tuck, which then starts dragging
    /// its own dot and opens its own menu.
    private func nextToDot(moving windowID: CGWindowID) -> ItemMover.Destination? {
        let snapshot = scanner.scan(resolveOwners: false)
        guard let dot = snapshot.dot else { return nil }
        let candidates = snapshot.items.filter { $0.windowID != windowID && $0.frame.maxX <= dot.frame.minX + 1 }
        if let neighbour = candidates.last, neighbour.placement != .hidden {
            return .rightOf(neighbour.windowID)
        }
        return snapshot.separator.map { .rightOf($0.windowID) }
    }

    // MARK: Open

    /// Where an item's menu should appear when it is opened from Tuck.
    enum OpenSpot {
        /// Next to the dot, where the dropdown was clicked.
        case dot
        /// Under the notch, where the drawer was clicked.
        case notch
    }

    /// Opens an item's menu. A menu opens wherever its item is, so an item that is hidden (or, from
    /// the dot, behind the notch) is first moved to `spot`, pressed there, and moved back once its
    /// menu or popover has closed. From the notch, items already behind it are pressed in place.
    func open(_ windowID: CGWindowID, at spot: OpenSpot = .dot) async {
        await rehideNow()
        let snapshot = scanner.scan()
        guard let item = snapshot.item(windowID) else { return }

        let inPlace = item.placement == .visible || item.placement == .pinned
            || (spot == .notch && item.placement == .overflow)
        guard !inPlace else {
            await press(item)
            return
        }
        let target: ItemMover.Destination? = switch spot {
        case .dot: nextToDot(moving: windowID)
        // Just right of the separator: the inner end of the menu bar, by the notch.
        case .notch: snapshot.separator.map { .rightOf($0.windowID) }
        }
        guard let destination = target, let returnTo = returnDestination(for: windowID) else {
            pressFallback(item)
            return
        }

        guard await mover.move(windowID, to: destination) else {
            pressFallback(item)
            return
        }
        if spot == .dot {
            _ = await waitUntil(timeout: .seconds(1)) { WindowList.entry(for: windowID)?.isOnScreen == true }
        }
        try? await Task.sleep(for: .milliseconds(60))

        let before = WindowList.onScreenWindowIDs()
        await press(item)
        tempShown = TempShown(windowID: windowID, returnTo: returnTo, windowsBefore: before, started: .now)
        watchTempShown()
    }

    /// The item's right-hand neighbour today, so it can be put back exactly where it was.
    private func returnDestination(for windowID: CGWindowID) -> ItemMover.Destination? {
        let top = controls.dotFrame?.minY ?? 0
        let all = WindowList.statusItems(menuBarTop: top)
        guard let index = all.firstIndex(where: { $0.windowID == windowID }), index + 1 < all.count else { return nil }
        return .leftOf(all[index + 1].windowID)
    }

    private func press(_ item: MenuBarItem) async {
        if let element = item.owner?.element, AX.press(element) {
            Log.info("pressed \(item.windowID)")
        } else {
            _ = await mover.click(item.windowID)
        }
    }

    private func pressFallback(_ item: MenuBarItem) {
        guard let element = item.owner?.element else { return }
        Log.info("open \(item.windowID): falling back to AXPress")
        AX.press(element)
    }

    /// Waits until whatever the click opened (menu, popover, window) is gone, then moves the item back.
    private func watchTempShown() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            var sawInterface = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, let shown = self.tempShown else { return }
                let opened = WindowList.onScreenWindowIDs().subtracting(shown.windowsBefore)
                if !opened.isEmpty { sawInterface = true }
                let elapsed = ContinuousClock.now - shown.started
                let interfaceClosed = sawInterface ? opened.isEmpty : elapsed > .seconds(3)
                if interfaceClosed && NSEvent.pressedMouseButtons == 0 {
                    self.enqueue { await self.rehideNow() }
                    return
                }
            }
        }
    }

    /// Puts a temporarily shown item back where it came from.
    func rehideNow() async {
        watcher?.cancel()
        watcher = nil
        guard let shown = tempShown else { return }
        tempShown = nil
        _ = await mover.move(shown.windowID, to: shown.returnTo, landed: pushedOffScreen)
        await settleSeparator()
    }

    // MARK: Separator

    /// Moves need a separator with a real width to drop onto.
    private func prepareSeparatorForMoves() async {
        guard controls.separatorState == .idle else { return }
        controls.apply(.expanded)
        _ = await waitUntil(timeout: .milliseconds(500)) {
            guard let separator = self.scanner.scan(resolveOwners: false).separator else { return false }
            return separator.frame.width > 20
        }
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// Collapses the separator when something is hidden, and makes it vanish when nothing is.
    func settleSeparator() async {
        try? await Task.sleep(for: .milliseconds(80))
        let hasHidden = scanner.scan(resolveOwners: false).hasHidden
        let desired: ControlItems.SeparatorState = hasHidden ? .collapsed : .idle
        if controls.separatorState != desired {
            controls.apply(desired)
        }
    }
}
