import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)

            Text("Tuck needs Accessibility access")
                .font(.title2.weight(.semibold))

            Text("""
                To move other apps' menu bar items and open them from the dot, macOS requires you to \
                allow Tuck under Privacy & Security › Accessibility. Tuck only reads where menu bar \
                items are and what they are called; it never reads screen contents and never uses \
                the network.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open System Settings") {
                Permissions.prompt()
                Permissions.openSettingsPane()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("This window closes by itself once access is granted.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 420)
    }
}
