import SwiftUI

// MARK: - Menüeinträge (Kontextmenü der Zeilen, Menü in der Detailansicht)

/// Gemeinsame Einträge „Als Nächstes“ / „Zur Warteschlange“ / „Entfernen“.
struct PlaybackQueueMenuItems: View {
    let item: ArchiveItem
    let isQueued: Bool

    var body: some View {
        if isQueued {
            Button {
                PlaybackQueueStore.shared.playNext(item)
            } label: {
                Label("Als Nächstes abspielen", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button(role: .destructive) {
                PlaybackQueueStore.shared.remove(item)
            } label: {
                Label("Aus Warteschlange entfernen", systemImage: "minus.circle")
            }
        } else {
            Button {
                PlaybackQueueStore.shared.playNext(item)
                PlaybackQueueFeedback.added()
            } label: {
                Label("Als Nächstes abspielen", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                PlaybackQueueStore.shared.enqueue(item)
                PlaybackQueueFeedback.added()
            } label: {
                Label("Zur Warteschlange hinzufügen", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
    }
}

enum PlaybackQueueFeedback {
    @MainActor
    static func added() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Menü-Button in der Detailansicht

/// Kleiner Button rechts neben „Abspielen“. Zeigt einen Haken, wenn die Ausgabe schon eingereiht ist.
struct PlaybackQueueDetailMenuButton: View {
    let item: ArchiveItem
    @ObservedObject private var queue = PlaybackQueueStore.shared

    var body: some View {
        let isQueued = queue.queuedTerminIDs.contains(item.terminID)
        Menu {
            PlaybackQueueMenuItems(item: item, isQueued: isQueued)
        } label: {
            Image(systemName: isQueued ? "text.badge.checkmark" : "text.badge.plus")
                .contentTransition(.identity)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(isQueued ? "In der Warteschlange" : "Zur Warteschlange")
        .help(isQueued ? "In der Warteschlange" : "Zur Warteschlange hinzufügen")
    }
}

// MARK: - Liste

/// Bearbeitbare Liste der kommenden Ausgaben. Tippen spielt ab (und entfernt aus der Warteschlange).
struct PlaybackQueueList: View {
    @ObservedObject private var queue = PlaybackQueueStore.shared
    var onPlay: (() -> Void)? = nil

    var body: some View {
        List {
            ForEach(queue.items) { item in
                row(item)
            }
            .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { queue.remove(atOffsets: $0) }
        }
        .overlay {
            if queue.isEmpty {
                ContentUnavailableView(
                    "Warteschlange leer",
                    systemImage: "text.line.last.and.arrowtriangle.forward",
                    description: Text("Über das Kontextmenü einer Ausgabe hinzufügen.")
                )
            }
        }
    }

    private func row(_ item: ArchiveItem) -> some View {
        HStack(spacing: 8) {
            Button {
                AudioPlayerManager.shared.play(item: item)
                onPlay?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sendungTitel.bitefm_sanitizedDisplayLine)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(item.datumDe) · \(item.subtitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Spielt diese Ausgabe sofort ab.")

            #if os(macOS)
            // Auf dem Mac gibt es kein Wischen zum Löschen.
            Button {
                queue.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aus Warteschlange entfernen")
            .help("Aus Warteschlange entfernen")
            #endif
        }
    }
}

/// Kopfzeile mit Titel und „Leeren“ — im Mac/iPad-Popover.
private struct PlaybackQueuePopoverContent: View {
    @ObservedObject private var queue = PlaybackQueueStore.shared
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Als Nächstes")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    queue.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(queue.isEmpty)
                .accessibilityLabel("Warteschlange leeren")
                .help("Warteschlange leeren")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            PlaybackQueueList(onPlay: close)
        }
        .frame(width: 340, height: 360)
    }
}

/// iPhone: Sheet mit Bearbeiten-Modus.
struct PlaybackQueueSheet: View {
    @ObservedObject private var queue = PlaybackQueueStore.shared
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    var body: some View {
        NavigationStack {
            PlaybackQueueList(onPlay: { dismiss() })
                .navigationTitle("Als Nächstes")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.editMode, $editMode)
                .onChange(of: queue.isEmpty) { _, isEmpty in
                    if isEmpty { editMode = .inactive }
                }
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .destructive) {
                            queue.clear()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(queue.isEmpty)
                        .accessibilityLabel("Warteschlange leeren")
                    }
                    #if os(iOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        } label: {
                            Image(systemName: editMode.isEditing ? "pencil.circle.fill" : "pencil")
                        }
                        .disabled(queue.isEmpty)
                        .accessibilityLabel(editMode.isEditing ? "Bearbeiten beenden" : "Bearbeiten")
                    }
                    #endif
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Fertig")
                    }
                }
        }
    }
}

// MARK: - Mini-Player (iPhone)

/// Unauffälliger Hinweis links vom Play/Pause-Button; nur sichtbar, wenn etwas eingereiht ist.
struct PlaybackQueueMiniButton: View {
    @ObservedObject private var queue = PlaybackQueueStore.shared
    @State private var isSheetPresented = false

    var body: some View {
        if !queue.isEmpty || isSheetPresented {
            Button {
                isSheetPresented = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .topTrailing) {
                        Text("\(queue.items.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .offset(x: 8, y: -6)
                    }
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Warteschlange, \(queue.items.count) Ausgaben")
            .sheet(isPresented: $isSheetPresented) {
                PlaybackQueueSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Player-Leiste (Mac/iPad)

/// `list.bullet` mit Zähler; nur sichtbar, wenn die Warteschlange nicht leer ist. Öffnet ein Popover.
struct PlaybackQueueBarButton: View {
    @ObservedObject private var queue = PlaybackQueueStore.shared
    @State private var isPresented = false

    var body: some View {
        if !queue.isEmpty || isPresented {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isPresented ? Color.white : Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(isPresented ? Color.accentColor : Color.clear)
                    .clipShape(Circle())
                    .overlay(alignment: .topTrailing) {
                        if !queue.isEmpty {
                            Text("\(queue.items.count)")
                                .font(.system(size: 9, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Capsule().fill(Color.accentColor))
                                .offset(x: 6, y: -5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Warteschlange, \(queue.items.count) Ausgaben")
            .help("Als Nächstes")
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                PlaybackQueuePopoverContent(close: { isPresented = false })
            }
        }
    }
}

// MARK: - „Danach: …“ (Wiedergabe-Sheet)

/// Dezente Zeile über den Bedienelementen im Wiedergabe-Sheet. Tippen öffnet die Liste.
struct PlaybackQueueUpNextRow: View {
    @ObservedObject private var queue = PlaybackQueueStore.shared
    @State private var isSheetPresented = false

    var body: some View {
        if let next = queue.nextItem {
            Button {
                isSheetPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .foregroundStyle(Color.accentColor)
                    Text("Danach: ")
                        .foregroundStyle(.secondary)
                    + Text(next.sendungTitel.bitefm_sanitizedDisplayLine)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    if queue.items.count > 1 {
                        Text("+\(queue.items.count - 1)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.footnote)
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Als Nächstes: \(next.sendungTitel), \(queue.items.count) in der Warteschlange")
            .sheet(isPresented: $isSheetPresented) {
                PlaybackQueueSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
