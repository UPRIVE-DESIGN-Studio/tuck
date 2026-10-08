import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the drawer (or the bar under the dot on a display without a notch) for the keyboard.
    static let openDrawer = Self("openDrawer", default: .init(.m, modifiers: [.control, .option]))
}
