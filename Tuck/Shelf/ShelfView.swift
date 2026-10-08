import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The row under the items in the drawer: now playing, a timer, and a file drop area.
struct ShelfView: View {
    let model: ShelfModel
    let onDark: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if model.showsNowPlaying, let playing = model.nowPlaying {
                NowPlayingCard(playing: playing, model: model)
            }
            if model.showsTimer {
                TimerCard(model: model)
            }
            if model.showsFiles {
                FilesCard(model: model)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(height: 52)
        .foregroundStyle(onDark ? .white : .primary)
        .environment(\.colorScheme, onDark ? .dark : .light)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct NowPlayingCard: View {
    let playing: NowPlaying
    let model: ShelfModel

    var body: some View {
        Card {
            HStack(spacing: 8) {
                artwork
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(playing.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(playing.artist).font(.system(size: 11)).opacity(0.7).lineLimit(1)
                }
                .frame(maxWidth: 150, alignment: .leading)
                HStack(spacing: 2) {
                    control("backward.fill", .previous)
                    control(playing.isPlaying ? "pause.fill" : "play.fill", .playPause)
                    control("forward.fill", .next)
                }
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let data = playing.artwork, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: playing.player.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "music.note")
        }
    }

    private func control(_ symbol: String, _ command: NowPlaying.Command) -> some View {
        Button { model.send(command) } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

private struct TimerCard: View {
    let model: ShelfModel

    var body: some View {
        Card {
            if let remaining = model.timerRemaining {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    Button { model.cancelTimer() } label: {
                        Image(systemName: "xmark.circle.fill").opacity(0.6)
                    }
                    .buttonStyle(.plain)
                    .help("Stop the timer")
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "timer").opacity(0.7)
                    ForEach([5, 15, 25], id: \.self) { minutes in
                        Button("\(minutes)") { model.startTimer(minutes: minutes) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .frame(width: 26, height: 22)
                            .background(.white.opacity(0.1), in: Capsule())
                            .help("\(minutes) minute timer")
                    }
                }
            }
        }
    }
}

private struct FilesCard: View {
    let model: ShelfModel
    @State private var targeted: Target?

    enum Target { case airDrop, keep }

    var body: some View {
        Card {
            HStack(spacing: 6) {
                dropTarget(.airDrop, symbol: "dot.radiowaves.left.and.right", title: "AirDrop") { model.airDrop($0) }
                dropTarget(.keep, symbol: "tray.and.arrow.down", title: "Keep") { model.keep($0) }
                ForEach(model.keptFiles, id: \.self) { url in
                    KeptFile(url: url) { model.remove(url) }
                }
            }
        }
    }

    private func dropTarget(_ target: Target, symbol: String, title: String, perform: @escaping ([URL]) -> Void) -> some View {
        VStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(title).font(.system(size: 9))
        }
        .frame(width: 44, height: 38)
        .background(.white.opacity(targeted == target ? 0.25 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(target == .airDrop ? "Drop files to send them with AirDrop" : "Drop files to keep them here; drag them out later")
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { targeted == target }, set: { targeted = $0 ? target : (targeted == target ? nil : targeted) }
        )) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let fileURL = URL(dataRepresentation: url, relativeTo: nil) {
                        urls.append(fileURL)
                    }
                }
                if !urls.isEmpty { perform(urls) }
            }
            return true
        }
    }
}

private struct KeptFile: View {
    let url: URL
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 30, height: 30)
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            .onHover { hovering = $0 }
            .help(url.lastPathComponent)
            .onDrag { NSItemProvider(object: url as NSURL) }
    }
}
