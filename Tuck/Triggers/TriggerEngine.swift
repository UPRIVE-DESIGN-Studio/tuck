import AppKit

/// Brings tucked items into the menu bar while their trigger holds, and puts them back after.
/// "Icon changes" triggers instead make the drawer peek open when the item's picture changes.
final class TriggerEngine {
    private let controller: TuckController
    private let store: ItemStore
    private let peek: () -> Void
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Items currently out because of their trigger. The auto-tucker leaves these alone.
    private(set) var shownByTrigger: Set<ItemKey> = []
    /// Last picture fingerprint per item with an "icon changes" trigger.
    private var fingerprints: [ItemKey: Int] = [:]
    private var lastPeek: [ItemKey: Date] = [:]

    init(controller: TuckController, store: ItemStore, peek: @escaping () -> Void) {
        self.controller = controller
        self.store = store
        self.peek = peek
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        })
    }

    func check() {
        let triggers = store.triggers
        // Also runs with no triggers left, to put back items whose trigger was just removed.
        guard !triggers.isEmpty || !shownByTrigger.isEmpty, Permissions.isTrusted, controller.isIdle else { return }
        let snapshot = controller.scanner.scan()
        let power = triggers.values.contains { $0 == .onBattery || { if case .batteryBelow = $0 { true } else { false } }($0) }
            ? Conditions.power() : nil
        let ssid = triggers.values.contains { if case .wifi = $0 { true } else { false } } ? WiFi.currentSSID() : nil
        let focus = triggers.values.contains(.focus) ? Conditions.focusIsOn(snapshot.items) : nil

        var appearanceItems: [MenuBarItem] = []
        for item in snapshot.items {
            guard let key = item.key, let trigger = triggers[key] else { continue }
            if trigger == .appearanceChanges {
                appearanceItems.append(item)
                continue
            }
            let holds = switch trigger {
            case .appFrontmost(let bundleID): Conditions.frontmostBundleID == bundleID
            case .onBattery: power?.onBattery ?? false
            case .batteryBelow(let percent): (power?.percent).map { $0 < percent } ?? false
            case .wifi(let name): ssid == name
            case .focus: focus ?? false
            case .appearanceChanges: false
            }
            if holds && !shownByTrigger.contains(key) && !item.isOnScreen {
                shownByTrigger.insert(key)
                Log.info("trigger: showing \(key) (\(trigger.summary))")
                controller.enqueue { [controller] in await controller.show(item.windowID) }
            } else if !holds && shownByTrigger.contains(key) {
                shownByTrigger.remove(key)
                Log.info("trigger: putting back \(key)")
                if store.mode(key) == .hide || store.isAutoTucked(key) {
                    controller.enqueue { [controller] in await controller.hide(item.windowID) }
                }
            }
        }
        // Items whose trigger was removed while they were out go back too.
        for key in shownByTrigger where triggers[key] == nil {
            shownByTrigger.remove(key)
            if let item = snapshot.items.first(where: { $0.key == key }), store.mode(key) == .hide {
                controller.enqueue { [controller] in await controller.hide(item.windowID) }
            }
        }
        if !appearanceItems.isEmpty { watchAppearance(appearanceItems) }
    }

    /// Captures each watched item and peeks the drawer when one looks different than last time.
    private func watchAppearance(_ items: [MenuBarItem]) {
        guard ItemImages.isAllowed else { return }
        Task {
            let pictures = await ItemImages().refresh(items)
            for item in items {
                guard let key = item.key, let picture = pictures[item.windowID],
                      let fingerprint = Self.fingerprint(picture)
                else { continue }
                defer { fingerprints[key] = fingerprint }
                guard let previous = fingerprints[key], previous != fingerprint else { continue }
                if let last = lastPeek[key], Date.now.timeIntervalSince(last) < 30 { continue }
                lastPeek[key] = .now
                Log.info("trigger: \(key) changed its icon")
                peek()
            }
        }
    }

    /// A coarse hash of an 8×8 grey thumbnail, so tiny rendering noise does not count as a change.
    private static func fingerprint(_ image: NSImage) -> Int? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var hasher = Hasher()
        for index in 0..<64 { hasher.combine(data[index] / 32) }
        return hasher.finalize()
    }
}
