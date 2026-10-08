import SwiftUI

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                if !model.accessibilityGranted {
                    Text("Grant Accessibility access below to see your menu bar items.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rows) { row in
                    ItemRow(row: row, isPending: model.pending.contains(row.id)) { hidden in
                        model.setHidden(hidden, for: row.id)
                    }
                }
            } header: {
                Text("Menu Bar Items")
            } footer: {
                Text("Hidden items live in the bar under the dot. Items the notch covers show up there too, without being hidden. Clock and Control Center always stay put.")
            }

            Section("General") {
                if model.hasNotch {
                    Toggle(isOn: Binding(get: { model.notchHover }, set: { model.setNotchHover($0) })) {
                        Text("Open by Hovering the Notch")
                        Text("Rest the pointer behind the notch to drop down the tucked items.")
                    }
                }
                Toggle("Open at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
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
                    detail: "Optional. Shows the real menu bar icons in the bar instead of app icons. Takes effect after Tuck restarts.",
                    granted: model.screenRecordingGranted,
                    action: model.requestScreenRecording
                )
            } header: {
                Text("Permissions")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit Tuck") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .task {
            // Items appear, move and change size while the window is open.
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct ItemRow: View {
    let row: SettingsModel.Row
    let isPending: Bool
    let setHidden: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
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
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isPending {
                ProgressView().controlSize(.small)
            }
            Toggle("Hide in Tuck", isOn: Binding(
                get: { row.placement == .hidden },
                set: setHidden
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isPending)
        }
    }

    private var status: String {
        switch row.placement {
        case .hidden: "Hidden in Tuck"
        case .overflow: "Behind the notch — reachable from the dot"
        case .visible, .pinned: "In the menu bar"
        }
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
