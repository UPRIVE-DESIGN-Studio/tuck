import Foundation
import Observation

/// What the user decided per menu bar item, persisted in UserDefaults.
@Observable
final class ItemStore {
    enum Mode: String, Codable, CaseIterable {
        /// Never tucked automatically. Behind the notch it is still reachable from the drawer.
        case show
        /// Tucked when the notch would cover something, least important first.
        case auto
        /// Always in Tuck.
        case hide
    }

    struct Record: Codable, Equatable {
        var mode: Mode
        var trigger: Trigger?
    }

    /// Everything that is saved, also the export / import format.
    struct Saved: Codable, Equatable {
        var records: [String: Record] = [:]
        /// Most important first. Important items sit next to the clock and are tucked last.
        var order: [String] = []
        /// Items Tuck tucked by itself and will bring back once there is room.
        var autoTucked: [String] = []
    }

    private static let defaultsKey = "itemStore"

    private(set) var saved: Saved
    @ObservationIgnored private let defaults: UserDefaults

    /// Clock and Control Center cannot be moved; Tuck never records or acts on them.
    static let fixedItems: Set<String> = [
        "com.apple.controlcenter|com.apple.menuextra.clock",
        "com.apple.controlcenter|com.apple.menuextra.controlcenter",
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           var decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            // Earlier builds could record these while several displays' rows were mixed up.
            let before = decoded
            decoded.autoTucked.removeAll(where: Self.fixedItems.contains)
            for key in Self.fixedItems { decoded.records[key] = nil }
            decoded.order.removeAll(where: Self.fixedItems.contains)
            saved = decoded
            if decoded != before { save() }
        } else {
            saved = Saved()
        }
    }

    // MARK: Reading

    func mode(_ key: ItemKey) -> Mode? { saved.records[key.rawValue]?.mode }
    func trigger(_ key: ItemKey) -> Trigger? { saved.records[key.rawValue]?.trigger }
    func isAutoTucked(_ key: ItemKey) -> Bool { saved.autoTucked.contains(key.rawValue) }
    var autoTuckedKeys: Set<ItemKey> { Set(saved.autoTucked.map(ItemKey.init)) }
    var triggers: [ItemKey: Trigger] {
        saved.records.reduce(into: [:]) { result, entry in
            if let trigger = entry.value.trigger { result[ItemKey(rawValue: entry.key)] = trigger }
        }
    }

    /// Position in the priority list; items never ranked come after every ranked one.
    func rank(_ key: ItemKey) -> Int {
        saved.order.firstIndex(of: key.rawValue) ?? (saved.order.count + 1_000)
    }

    // MARK: Writing

    /// Records first-seen items, ranked by where they sit now (nearest the clock first). On the
    /// very first run, items already hidden were hidden by the user and become Hide. Later, new
    /// items become Auto: macOS adds new items at the far left, inside the hidden section, so
    /// they are marked as tucked by Tuck and come out once there is room.
    @discardableResult
    func adopt(_ items: [MenuBarItem]) -> Bool {
        let firstRun = saved.records.isEmpty
        var changed = false
        for item in items.reversed() {
            guard let key = item.key, item.placement != .pinned, !Self.fixedItems.contains(key.rawValue) else { continue }
            if saved.records[key.rawValue] == nil {
                let userHidden = firstRun && item.placement == .hidden
                saved.records[key.rawValue] = Record(mode: userHidden ? .hide : .auto)
                if !userHidden && item.placement == .hidden && !saved.autoTucked.contains(key.rawValue) {
                    saved.autoTucked.append(key.rawValue)
                }
                changed = true
            }
            if !saved.order.contains(key.rawValue) {
                saved.order.append(key.rawValue)
                changed = true
            }
        }
        if changed { save() }
        return changed
    }

    func setMode(_ mode: Mode, for key: ItemKey) {
        saved.records[key.rawValue, default: Record(mode: mode)].mode = mode
        saved.autoTucked.removeAll { $0 == key.rawValue }
        save()
    }

    func setTrigger(_ trigger: Trigger?, for key: ItemKey) {
        saved.records[key.rawValue, default: Record(mode: .auto)].trigger = trigger
        save()
    }

    func setOrder(_ keys: [ItemKey]) {
        let ranked = keys.map(\.rawValue)
        saved.order = ranked + saved.order.filter { !ranked.contains($0) }
        save()
    }

    func markAutoTucked(_ key: ItemKey, _ tucked: Bool) {
        saved.autoTucked.removeAll { $0 == key.rawValue }
        if tucked { saved.autoTucked.append(key.rawValue) }
        save()
    }

    func replace(with imported: Saved) {
        saved = imported
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
