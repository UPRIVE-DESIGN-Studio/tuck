import SwiftUI

/// Popover for choosing when a tucked item should come into the menu bar on its own.
struct TriggerEditor: View {
    enum Kind: String, CaseIterable, Identifiable {
        case none, app, onBattery, batteryBelow, wifi, focus, appearance
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "Never"
            case .app: "While an app is in front"
            case .onBattery: "While on battery"
            case .batteryBelow: "While battery is low"
            case .wifi: "While on a Wi‑Fi network"
            case .focus: "While a Focus is on"
            case .appearance: "Peek when its icon changes"
            }
        }
    }

    let save: (Trigger?) -> Void
    @State private var kind: Kind
    @State private var bundleID: String
    @State private var percent: Int
    @State private var ssid: String
    @Environment(\.dismiss) private var dismiss

    init(trigger: Trigger?, save: @escaping (Trigger?) -> Void) {
        self.save = save
        var kind = Kind.none, bundleID = "", percent = 20, ssid = ""
        switch trigger {
        case .appFrontmost(let id): kind = .app; bundleID = id
        case .onBattery: kind = .onBattery
        case .batteryBelow(let value): kind = .batteryBelow; percent = value
        case .wifi(let name): kind = .wifi; ssid = name
        case .focus: kind = .focus
        case .appearanceChanges: kind = .appearance
        case nil: break
        }
        _kind = State(initialValue: kind)
        _bundleID = State(initialValue: bundleID)
        _percent = State(initialValue: percent)
        _ssid = State(initialValue: ssid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring into the menu bar").font(.headline)
            Picker("When", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()

            switch kind {
            case .app:
                Picker("App", selection: $bundleID) {
                    Text("Choose…").tag("")
                    ForEach(RunningApps.regular, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
            case .batteryBelow:
                Stepper("Below \(percent) %", value: $percent, in: 5...95, step: 5)
            case .wifi:
                TextField("Network name", text: $ssid)
                    .textFieldStyle(.roundedBorder)
                Button("Use Current Network") { ssid = WiFi.currentSSID() ?? ssid }
                    .buttonStyle(.link)
                Text("Reading the network name needs Location access.")
                    .font(.caption).foregroundStyle(.secondary)
            case .appearance:
                Text("Needs Screen Recording. The notch drawer opens for a moment with this item highlighted.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }

            HStack {
                Spacer()
                Button("Done") {
                    save(trigger)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(kind == .app && bundleID.isEmpty || kind == .wifi && ssid.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var trigger: Trigger? {
        switch kind {
        case .none: nil
        case .app: .appFrontmost(bundleID: bundleID)
        case .onBattery: .onBattery
        case .batteryBelow: .batteryBelow(percent: percent)
        case .wifi: .wifi(ssid: ssid)
        case .focus: .focus
        case .appearance: .appearanceChanges
        }
    }
}

enum RunningApps {
    struct App {
        let bundleID: String
        let name: String
    }

    static var regular: [App] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { App(bundleID: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
