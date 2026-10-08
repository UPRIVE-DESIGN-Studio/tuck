import AppKit
import UniformTypeIdentifiers

/// Settings export / import as one JSON file: item modes, ranks and triggers, preferences, hotkey.
struct Backup: Codable, Equatable {
    var version = 1
    var items: ItemStore.Saved
    var preferences: [String: Bool]
    /// KeyboardShortcuts' own stored value for the drawer hotkey.
    var hotkey: String?

    static let preferenceKeys = [
        "notchHover", "autoTuck", "revealOnPlainDisplays", "showCount", "shelfNowPlaying", "shelfTimer", "shelfFiles",
    ]
    private static let hotkeyKey = "KeyboardShortcuts_openDrawer"

    static func current(_ store: ItemStore, defaults: UserDefaults = .standard) -> Backup {
        let preferences = preferenceKeys.reduce(into: [String: Bool]()) { result, key in
            if let value = defaults.object(forKey: key) as? Bool { result[key] = value }
        }
        return Backup(items: store.saved, preferences: preferences, hotkey: defaults.string(forKey: hotkeyKey))
    }

    func apply(to store: ItemStore, defaults: UserDefaults = .standard) {
        store.replace(with: items)
        for (key, value) in preferences where Self.preferenceKeys.contains(key) {
            defaults.set(value, forKey: key)
        }
        if let hotkey { defaults.set(hotkey, forKey: Self.hotkeyKey) }
    }

    @MainActor
    static func export(_ store: ItemStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tuck Settings.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(current(store)).write(to: url)
        } catch {
            Log.error("export failed: \(error.localizedDescription)")
        }
    }

    /// Returns true when a file was imported.
    @MainActor
    static func importFile(into store: ItemStore) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url))
            backup.apply(to: store)
            return true
        } catch {
            Log.error("import failed: \(error.localizedDescription)")
            NSAlert(error: error).runModal()
            return false
        }
    }
}
