import SwiftUI

/// Reorderable native Up Next queue drawer with Now Playing, drag-to-reorder Queued items,
/// active context queue, and Autoplay toggle.
struct QueueDrawerView: View {
    @Bindable var app: AppController

    var body: some View {
        let audio = app.audio
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if audio.queue.upcomingCount > 0 {
                    Button("Clear") { audio.clearUpcoming() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            List {
                if let current = audio.currentTrack {
                    Section("Now Playing") {
                        queueRow(current, isCurrent: true, onRemove: nil)
                    }
                }

                if !audio.queue.userUpNext.isEmpty {
                    Section("Queued") {
                        ForEach(Array(audio.queue.userUpNext.enumerated()), id: \.element.id) { idx, track in
                            queueRow(track, isCurrent: false) {
                                audio.removeUserUpNext(at: IndexSet(integer: idx))
                            }
                        }
                        .onMove { source, destination in
                            audio.moveUserUpNext(fromOffsets: source, toOffset: destination)
                        }
                    }
                }

                if !audio.queue.contextQueue.isEmpty {
                    Section("From \(audio.queue.contextTitle ?? "Queue")") {
                        ForEach(Array(audio.queue.contextQueue.prefix(60).enumerated()), id: \.element.id) { idx, track in
                            queueRow(track, isCurrent: false) {
                                audio.removeFromContext(at: IndexSet(integer: idx))
                            }
                        }
                    }
                }

                if audio.queue.autoplayEnabled && !audio.queue.autoplayQueue.isEmpty {
                    Section("Autoplay") {
                        ForEach(audio.queue.autoplayQueue.prefix(20)) { track in
                            queueRow(track, isCurrent: false, onRemove: nil)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Toggle(isOn: Binding(
                    get: { audio.queue.autoplayEnabled },
                    set: { audio.setAutoplayEnabled($0) }
                )) {
                    Text("Autoplay similar tracks")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func queueRow(_ track: SCTrack, isCurrent: Bool, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: 9) {
            CachedArtwork(url: track.resolvedArtworkURL(size: .small), size: 34, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent else { return }
            app.audio.play(track: track, inContext: app.audio.queue.contextQueue, contextTitle: app.audio.queue.contextTitle)
        }
    }
}
