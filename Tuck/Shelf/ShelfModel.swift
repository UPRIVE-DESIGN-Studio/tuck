import AppKit
import Observation

/// State behind the shelf row: now playing, a timer, and files kept on the shelf.
@Observable
final class ShelfModel {
    private(set) var nowPlaying: NowPlaying?
    private(set) var timerEnd: Date?
    private(set) var now = Date.now
    private(set) var keptFiles: [URL] = []

    var showsNowPlaying = Preferences.shelfNowPlaying
    var showsTimer = Preferences.shelfTimer
    var showsFiles = Preferences.shelfFiles
    var isEmpty: Bool { !showsNowPlaying && !showsTimer && !showsFiles }

    /// The timer ran out: the drawer peeks open.
    @ObservationIgnored var onTimerDone: () -> Void = {}

    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init() {
        keptFiles = (UserDefaults.standard.stringArray(forKey: "shelfFiles") ?? [])
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Now playing

    /// Polls the players once a second while the drawer is open.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.now = .now
                if self.showsNowPlaying {
                    let playing = await NowPlaying.current()
                    if playing != self.nowPlaying { self.nowPlaying = playing }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    func send(_ command: NowPlaying.Command) {
        guard let player = nowPlaying?.player else { return }
        NowPlaying.send(command, to: player)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            nowPlaying = await NowPlaying.current()
        }
    }

    // MARK: Timer

    var timerRemaining: TimeInterval? {
        timerEnd.map { max(0, $0.timeIntervalSince(now)) }
    }

    func startTimer(minutes: Int) {
        timerEnd = .now.addingTimeInterval(TimeInterval(minutes * 60))
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let end = self.timerEnd else { return }
                self.now = .now
                if end <= .now {
                    self.timerEnd = nil
                    NSSound(named: "Glass")?.play()
                    self.onTimerDone()
                    return
                }
            }
        }
    }

    func cancelTimer() {
        timerTask?.cancel()
        timerEnd = nil
    }

    // MARK: Files

    func keep(_ urls: [URL]) {
        keptFiles = Array(NSOrderedSet(array: keptFiles + urls)) as? [URL] ?? keptFiles + urls
        saveFiles()
    }

    func remove(_ url: URL) {
        keptFiles.removeAll { $0 == url }
        saveFiles()
    }

    func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            Log.error("AirDrop unavailable")
            return
        }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    private func saveFiles() {
        UserDefaults.standard.set(keptFiles.map(\.path), forKey: "shelfFiles")
    }
}
