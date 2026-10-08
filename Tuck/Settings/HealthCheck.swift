import AppKit

/// Checks that the techniques Tuck relies on still work. Every macOS release can change how the
/// menu bar is hosted, so this runs by itself after the system version changes.
enum HealthCheck {
    struct Result: Identifiable {
        let name: String
        let passed: Bool
        let detail: String
        var id: String { name }
    }

    struct Report {
        let date: Date
        let system: String
        let results: [Result]
        var passed: Bool { results.allSatisfy(\.passed) }
    }

    static var systemVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    /// Reads only; moves nothing.
    static func passive(_ controller: TuckController) -> [Result] {
        let trusted = Permissions.isTrusted
        var results = [Result(name: "Accessibility", passed: trusted, detail: trusted ? "Allowed" : "Not allowed")]
        guard trusted else { return results }

        let snapshot = controller.scanner.scan()
        results.append(Result(
            name: "Menu bar items found", passed: !snapshot.items.isEmpty, detail: "\(snapshot.items.count) items"
        ))
        let own = snapshot.dot != nil && snapshot.separator != nil
        results.append(Result(name: "Tuck's own items found", passed: own, detail: own ? "Dot and separator" : "Missing"))
        let resolved = snapshot.items.filter { $0.owner != nil }.count
        let ratio = snapshot.items.isEmpty ? 0 : Double(resolved) / Double(snapshot.items.count)
        results.append(Result(
            name: "Owners identified", passed: ratio >= 0.8, detail: "\(resolved) of \(snapshot.items.count)"
        ))
        let hidden = snapshot.items.filter { $0.placement == .hidden }
        if controller.controls.separatorState == .collapsed, !hidden.isEmpty {
            let offScreen = hidden.allSatisfy { !$0.isOnScreen || $0.frame.maxX <= 0 }
            results.append(Result(
                name: "Hidden section", passed: offScreen, detail: offScreen ? "\(hidden.count) items off-screen" : "Hidden items are visible"
            ))
        }
        return results
    }

    /// Moves one hidden item out and back in, the riskiest thing Tuck does.
    static func moveTest(_ controller: TuckController) async -> Result? {
        let snapshot = controller.scanner.scan(resolveOwners: false)
        guard let item = snapshot.items.first(where: { $0.placement == .hidden }), let separator = snapshot.separator
        else { return nil }
        let out = await controller.relocate(item.windowID, to: .rightOf(separator.windowID))
        await controller.hide(item.windowID)
        let back = controller.scanner.scan(resolveOwners: false).item(item.windowID)?.placement == .hidden
        return Result(
            name: "Moving items", passed: out && back,
            detail: out && back ? "Out and back in" : out ? "Came out but did not go back" : "Did not come out"
        )
    }

    static func run(_ controller: TuckController) async -> Report {
        // The window server reports new positions a moment after the separator changes.
        try? await Task.sleep(for: .seconds(1))
        var results = passive(controller)
        if results.allSatisfy(\.passed), let move = await moveTest(controller) { results.append(move) }
        let report = Report(date: .now, system: systemVersion, results: results)
        Log.info("health check on \(report.system): " + results.map { "\($0.name) \($0.passed ? "ok" : "FAILED") (\($0.detail))" }.joined(separator: "; "))
        return report
    }
}
