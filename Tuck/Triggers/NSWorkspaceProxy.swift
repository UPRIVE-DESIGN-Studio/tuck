import AppKit

enum NSWorkspaceProxy {
    static func urlForApplication(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
