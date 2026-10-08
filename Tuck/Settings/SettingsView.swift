import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let model: SettingsModel
    let shelf: ShelfModel

    var body: some View {
        TabView {
            ItemsTab(model: model)
                .tabItem { Label("Items", systemImage: "menubar.rectangle") }
            ShelfTab(shelf: shelf)
                .tabItem { Label("Shelf", systemImage: "tray") }
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 640)
        .task {
            // Items appear, move and change size while the window is open.
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: Items

private struct ItemsTab: View {
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Tuck automatically when the notch would cover items", isOn: Binding(
                    get: { model.autoTuck }, set: { model.setAutoTuck($0) }
                ))
                Text("Drag to rank. Items at the top sit next to the clock and are tucked last. **Show** is never tucked, **Auto** is tucked when space runs out, **Hide** always lives in Tuck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            if !model.accessibilityGranted {
                ContentUnavailableView(
                    "Accessibility access needed", systemImage: "lock",
                    description: Text("Allow Tuck in the General tab to see your menu bar items.")
                )
            } else {
                List {
                    ForEach(model.rows) { row in
                        ItemRow(row: row, model: model)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

private struct ItemRow: View {
    let row: SettingsModel.Row
    let model: SettingsModel
    @State private var editingTrigger = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "questionmark.square.dashed").resizable()
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.pending.contains(row.key) {
                ProgressView().controlSize(.small)
            }
            Button {
                editingTrigger = true
            } label: {
                Image(systemName: row.trigger == nil ? "bolt" : "bolt.fill")
                    .foregroundStyle(row.trigger == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.borderless)
            .help(row.trigger?.summary ?? "Show this item when…")
            .popover(isPresented: $editingTrigger, arrowEdge: .bottom) {
                TriggerEditor(trigger: row.trigger) { model.setTrigger($0, for: row) }
            }
            Picker("Mode", selection: Binding(get: { row.mode }, set: { model.setMode($0, for: row) })) {
                Text("Show").tag(ItemStore.Mode.show)
                Text("Auto").tag(ItemStore.Mode.auto)
                Text("Hide").tag(ItemStore.Mode.hide)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
            .disabled(model.pending.contains(row.key))
        }
        .padding(.vertical, 2)
    }

    private var status: String {
        var text = switch row.placement {
        case .hidden where row.isOnScreen: "In the menu bar (display without a notch)"
        case .hidden where row.isAutoTucked: "Tucked automatically — no room"
        case .hidden: "Hidden in Tuck"
        case .overflow: "Behind the notch — reachable from the dot"
        case .visible, .pinned: "In the menu bar"
        }
        if let trigger = row.trigger { text += " · \(trigger.summary)" }
        return text
    }
}

// MARK: Shelf

private struct ShelfTab: View {
    @Bindable var shelf: ShelfModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $shelf.showsNowPlaying) {
                    Text("Now playing")
                    Text("Spotify or Music: title, artist, play and skip. macOS asks once for permission to control each app.")
                }
                Toggle(isOn: $shelf.showsTimer) {
                    Text("Timer")
                    Text("5, 15 or 25 minutes. When it ends, a sound plays and the drawer peeks open.")
                }
                Toggle(isOn: $shelf.showsFiles) {
                    Text("Files")
                    Text("Drag files onto the notch, then drop them on AirDrop to send or Keep to park them until you drag them out.")
                }
            } header: {
                Text("Under the items in the drawer")
            }
        }
        .formStyle(.grouped)
        .onChange(of: shelf.showsNowPlaying) { Preferences.shelfNowPlaying = shelf.showsNowPlaying }
        .onChange(of: shelf.showsTimer) { Preferences.shelfTimer = shelf.showsTimer }
        .onChange(of: shelf.showsFiles) { Preferences.shelfFiles = shelf.showsFiles }
    }
}

// MARK: General

private struct GeneralTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle(isOn: Binding(get: { model.revealOnPlainDisplays }, set: { model.setRevealOnPlainDisplays($0) })) {
                    Text("Show everything on displays without a notch")
                    Text("On an external display, hidden items appear in the menu bar too.")
                }
                Toggle(isOn: Binding(get: { model.showCount }, set: { model.setShowCount($0) })) {
                    Text("Show count next to the dot")
                    Text("How many items are behind the notch or tucked automatically.")
                }
                if model.hasNotch {
                    Toggle(isOn: Binding(get: { model.notchHover }, set: { model.setNotchHover($0) })) {
                        Text("Open by hovering the notch")
                        Text("Rest the pointer behind the notch to drop down the tucked items.")
                    }
                }
            }

            Section("Keyboard") {
                KeyboardShortcuts.Recorder("Open the drawer:", name: .openDrawer)
                Text("Then use ← → and Return to open an item, ⌥Return for its alternate menu, or start typing to search every item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Button("Export…", action: model.exportSettings)
                    Button("Import…", action: model.importSettings)
                }
            } header: {
                Text("Settings File")
            } footer: {
                Text("Item modes, ranks, triggers, preferences and the hotkey, as JSON.")
            }

            Section {
                if let report = model.health {
                    ForEach(report.results) { result in
                        LabeledContent {
                            Text(result.detail).foregroundStyle(result.passed ? Color.secondary : Color.red)
                        } label: {
                            Label(result.name, systemImage: result.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.passed ? Color.green : Color.orange)
                        }
                    }
                    Text("Checked \(report.date.formatted(date: .abbreviated, time: .shortened)) on \(report.system)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if model.isCheckingHealth { ProgressView().controlSize(.small) }
                    Button("Run Check", action: model.runHealthCheck).disabled(model.isCheckingHealth)
                }
            } header: {
                Text("Health")
            } footer: {
                Text("Runs by itself after a macOS update. Moves one hidden item out and back in to make sure moving still works.")
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Required to find, move and open menu bar items.",
                    granted: model.accessibilityGranted
                ) {
                    Permissions.prompt()
                    Permissions.openSettingsPane()
                }
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Optional. Shows the real menu bar icons in the drawer instead of app icons, and lets an item peek when its icon changes. Takes effect after Tuck restarts.",
                    granted: model.screenRecordingGranted,
                    action: model.requestScreenRecording
                )
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit Tuck") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Allow…", action: action)
            }
        }
    }
}
