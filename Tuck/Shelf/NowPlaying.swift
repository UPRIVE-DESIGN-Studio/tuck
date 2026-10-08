import AppKit

/// What Spotify or Apple Music is playing, read and controlled through their AppleScript
/// dictionaries. Apps are only asked while they are running, so nothing gets launched.
struct NowPlaying: Equatable, Sendable {
    enum Player: String, Sendable {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }
    }

    let player: Player
    let title: String
    let artist: String
    let isPlaying: Bool
    /// Only Music hands over the artwork itself; Spotify gives a web address, which Tuck does not fetch.
    let artwork: Data?

    /// The playing app first, then a paused one.
    static func current() async -> NowPlaying? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let players = [Player.spotify, .music].filter { running.contains($0.bundleID) }
        guard !players.isEmpty else { return nil }
        return await Task.detached {
            let states = players.compactMap(read)
            return states.first(where: \.isPlaying) ?? states.first
        }.value
    }

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    static func send(_ command: Command, to player: Player) {
        Task.detached {
            _ = run("tell application \"\(player.rawValue)\" to \(command.rawValue)")
        }
    }

    private nonisolated static func read(_ player: Player) -> NowPlaying? {
        let script = """
            tell application "\(player.rawValue)"
                if player state is stopped then return {"stopped"}
                set t to current track
                return {player state as text, name of t, artist of t}
            end tell
            """
        guard let result = run(script), result.numberOfItems >= 3,
              let state = result.atIndex(1)?.stringValue, state != "stopped"
        else { return nil }
        var artwork: Data?
        if player == .music {
            artwork = run("tell application \"Music\" to get data of artwork 1 of current track")?.data
        }
        return NowPlaying(
            player: player, title: result.atIndex(2)?.stringValue ?? "", artist: result.atIndex(3)?.stringValue ?? "",
            isPlaying: state == "playing", artwork: artwork
        )
    }

    private nonisolated static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
