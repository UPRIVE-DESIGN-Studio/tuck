import Foundation
import os

/// Writes to the unified log and to `~/Library/Logs/Tuck.log`, so a session can be followed with `tail -f`.
enum Log {
    private static let logger = Logger(subsystem: "design.uprive.tuck", category: "app")
    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Tuck.log")
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR " + message)
    }

    private static func append(_ message: String) {
        let line = "\(timestamp.string(from: .now)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
