import AppKit
import ApplicationServices

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "would like to control this computer" prompt (once per signature).
    /// The key is `kAXTrustedCheckOptionPrompt`, spelled out because the global is not concurrency-safe.
    static func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettingsPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
