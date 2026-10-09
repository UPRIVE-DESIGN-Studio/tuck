import AppKit

/// Runs `AutoTuckPlanner` against the live menu bar. Checks after screen changes, app launches
/// and quits, and every few seconds as a safety net, but only does the expensive owner scan when
/// something is actually covered or there is room to bring an item back.
final class AutoTucker {
    private let controller: TuckController
    private let store: ItemStore
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// Items just tucked because they did not fit; not brought back for a minute, so live-text
    /// items that change width do not flip back and forth.
    private var cooling: [ItemKey: Date] = [:]

    /// Called after every check with the number of items out of sight that the user did not hide.
    var onCountChange: (Int) -> Void = { _ in }
    /// Items a trigger brought out; treated as Show until the trigger ends.
    var exempt: () -> Set<ItemKey> = { [] }

    init(controller: TuckController, store: ItemStore) {
        self.controller = controller
        self.store = store
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule(after: .seconds(1)) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: .seconds(1)) }
        })
        schedule(after: .seconds(1))
    }

    /// Debounced: many notifications in a row lead to one check.
    func schedule(after delay: Duration = .milliseconds(300), enforceModes: Bool = false) {
        if enforceModes { modesNeedEnforcing = true }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.controller.enqueue { await self.run() }
        }
    }

    /// Takes up to a few steps, re-measuring after each move.
    private func run() async {
        guard Cursor.isStill else {
            schedule(after: .seconds(1.5))
            return
        }
        await controller.settleSeparator()
        for _ in 0..<8 {
            guard let step = plan() else { break }
            await perform(step)
            try? await Task.sleep(for: .milliseconds(250))
        }
        reportCount()
    }

    private func plan() -> AutoTuckPlanner.Step? {
        guard Preferences.autoTuck, Permissions.isTrusted, controller.isIdle,
              NSEvent.pressedMouseButtons == 0, Cursor.isStill
        else { return nil }

        // Cheap first look without asking every app for its items.
        let roomy = TuckController.hasRoomyDisplay
        let quick = controller.scanner.scan(resolveOwners: false)
        let covered = !roomy && quick.items.contains { $0.placement.isVisibleSide && !$0.isOnScreen }
        let free = freeWidth(quick)
        let mayRestore = !store.autoTuckedKeys.isEmpty && (roomy || free > 20)
        guard covered || mayRestore || modesNeedEnforcing else { return nil }

        let snapshot = controller.scanner.scan()
        if store.adopt(snapshot.items) { Log.info("auto-tuck: adopted new items") }
        let now = Date.now
        cooling = cooling.filter { now.timeIntervalSince($0.value) < 60 }

        let candidates = snapshot.items.compactMap { item -> AutoTuckPlanner.Candidate? in
            guard let key = item.key, item.placement != .pinned else { return nil }
            let mode = exempt().contains(key) ? .show : store.mode(key) ?? .auto
            return AutoTuckPlanner.Candidate(
                key: key, width: item.frame.width, placement: item.placement, isOnScreen: item.isOnScreen,
                mode: mode, rank: store.rank(key)
            )
        }
        let step = AutoTuckPlanner.next(
            candidates, autoTucked: store.autoTuckedKeys, freeWidth: free, cooling: Set(cooling.keys), roomy: roomy
        )
        if step == nil { modesNeedEnforcing = false }
        return step
    }

    /// Set when the user changes a mode, so the next check also runs with nothing covered.
    var modesNeedEnforcing = true

    private func perform(_ step: AutoTuckPlanner.Step) async {
        let snapshot = controller.scanner.scan()
        switch step {
        case .tuck(let key):
            guard let item = snapshot.items.first(where: { $0.key == key }) else { return }
            Log.info("auto-tuck: tucking \(key)")
            await controller.hide(item.windowID)
            if store.mode(key) == .auto {
                store.markAutoTucked(key, true)
                cooling[key] = .now
            }
        case .restore(let key):
            guard let item = snapshot.items.first(where: { $0.key == key }) else { return }
            Log.info("auto-tuck: bringing back \(key)")
            await controller.place(item.windowID, rank: store.rank(key), ranks: store.rank)
            store.markAutoTucked(key, false)
        }
    }

    /// Points between the leftmost visible item and whatever limits the menu bar on that side:
    /// the notch, or the frontmost app's menus on a display without one.
    private func freeWidth(_ snapshot: ItemScanner.Snapshot) -> CGFloat {
        guard let dot = snapshot.dot else { return 0 }
        let leftmost = snapshot.items
            .filter { $0.placement == .visible && $0.isOnScreen }
            .map(\.frame.minX).min() ?? dot.frame.minX
        let screen = NSScreen.screens.first { $0.frame.minX <= dot.frame.midX && dot.frame.midX < $0.frame.maxX }
        let limit: CGFloat
        if let screen, let notch = NotchSensor.notchRect(of: screen) {
            limit = notch.maxX
        } else {
            limit = AppMenus.rightEdge() ?? (screen?.frame.minX ?? 0) + 400
        }
        return leftmost - limit
    }

    private func reportCount() {
        let snapshot = controller.scanner.scan(resolveOwners: false)
        let hiddenByUser = snapshot.items.filter { $0.placement == .hidden }.count - store.autoTuckedKeys.count
        let outOfSight = snapshot.tucked.count - max(0, hiddenByUser)
        onCountChange(max(0, outOfSight))
    }
}

/// The right edge of the frontmost app's menus (File, Edit, …), in screen points.
enum AppMenus {
    static func rightEdge() -> CGFloat? {
        guard let app = NSWorkspace.shared.menuBarOwningApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let bar = AX.attribute(element, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return nil }
        return AX.children(bar as! AXUIElement).compactMap { AX.frame($0)?.maxX }.max()
    }
}
