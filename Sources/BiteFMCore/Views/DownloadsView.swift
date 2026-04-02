#if os(iOS)
import SwiftUI
import SwiftData

/// Tab „Downloads“: heruntergeladene Sendungen, Verwaltung und Einstellungen.
struct DownloadsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var downloadManager: IOSDownloadManager
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var apiClient: APIClient

    @Query(sort: [
        SortDescriptor(\StoredDownloadedEpisode.broadcastDate, order: .reverse),
        SortDescriptor(\StoredDownloadedEpisode.terminID, order: .reverse)
    ])
    private var allEpisodes: [StoredDownloadedEpisode]

    @State private var selectedForDetail: ArchiveItem?
    @State private var isInspectorPresented = false
    @State private var showSettings = false
    @State private var showDeleteAllConfirm = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<Int>()

    private var listRows: [StoredDownloadedEpisode] {
        allEpisodes.sorted { lhs, rhs in
            let lRank = rowRank(lhs)
            let rRank = rowRank(rhs)
            if lRank != rRank { return lRank < rRank }
            if lhs.broadcastDate != rhs.broadcastDate { return lhs.broadcastDate > rhs.broadcastDate }
            return lhs.terminID > rhs.terminID
        }
    }

    /// Downloading/queued first, then failed, then completed (still date order within groups).
    private func rowRank(_ row: StoredDownloadedEpisode) -> Int {
        switch row.status {
        case .downloading, .queued, .preparing: return 0
        case .failed: return 1
        case .downloaded: return 2
        }
    }

    /// Summe der fertigen Downloads (inkl. Dateigröße von der Platte, falls `fileSizeBytes` fehlt).
    private var totalDownloadedAudioBytes: Int64 {
        listRows
            .filter { $0.status == .downloaded }
            .reduce(Int64(0)) { $0 + IOSDownloadManager.effectiveDownloadedAudioBytes(for: $1) }
    }

    var body: some View {
        Group {
            if listRows.isEmpty {
                ContentUnavailableView(
                    "Keine Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Lade Sendungen aus dem Archiv oder den Favoriten herunter, um sie offline anzuhören.")
                )
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(listRows, id: \.terminID) { row in
                            let item = row.toArchiveItem()
                            BroadcastRow(
                                item: item,
                                metaLineSizeSuffix: downloadSizeLabel(for: row),
                                selectedItemForDetail: $selectedForDetail,
                                isInspectorPresented: $isInspectorPresented
                            )
                            .tag(row.terminID)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    selection.remove(row.terminID)
                                    try? IOSDownloadManager.deleteDownloadedEpisode(terminID: row.terminID, context: modelContext)
                                    Task { await downloadManager.refreshSnapshotFromStore() }
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        if totalDownloadedAudioBytes > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Heruntergeladen insgesamt")
                                Spacer(minLength: 8)
                                Text(Self.formatStorageBytes(totalDownloadedAudioBytes))
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                        }
                    }
                }
                .environment(\.editMode, $editMode)
                .onChange(of: listRows.map(\.terminID)) { _, ids in
                    let valid = Set(ids)
                    selection = selection.intersection(valid)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                        if editMode == .inactive { selection.removeAll() }
                    }
                } label: {
                    if editMode == .active {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "pencil")
                            .fontWeight(.semibold)
                    }
                }
                .accessibilityLabel(editMode == .active ? "Fertig" : "Bearbeiten")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if editMode == .active, !selection.isEmpty {
                        Button("Löschen (\(selection.count))", role: .destructive) {
                            for id in selection {
                                try? IOSDownloadManager.deleteDownloadedEpisode(terminID: id, context: modelContext)
                            }
                            selection.removeAll()
                            withAnimation {
                                editMode = .inactive
                            }
                            Task { await downloadManager.refreshSnapshotFromStore() }
                        }
                    }
                    Button {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("Alle löschen", systemImage: "trash")
                    }
                    .disabled(listRows.isEmpty)
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Download-Einstellungen")
                }
            }
        }
        .broadcastInspector(isPresented: $isInspectorPresented, selectedItem: $selectedForDetail)
        .sheet(isPresented: $showSettings) {
            DownloadsSettingsView()
                .environmentObject(downloadManager)
        }
        .alert("Alle Downloads löschen?", isPresented: $showDeleteAllConfirm) {
            Button("Alle löschen", role: .destructive) {
                deleteAllDownloads()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle heruntergeladenen Sendungen und zugehörigen Dateien werden von diesem Gerät entfernt.")
        }
        .task {
            await downloadManager.runForegroundMaintenance()
        }
    }

    private func deleteAllDownloads() {
        let fd = FetchDescriptor<StoredDownloadedEpisode>()
        guard let rows = try? modelContext.fetch(fd) else { return }
        let ids = rows.map(\.terminID)
        for id in ids {
            try? IOSDownloadManager.deleteDownloadedEpisode(terminID: id, context: modelContext)
        }
        Task { await downloadManager.refreshSnapshotFromStore() }
    }

    /// MB-Anzeige: fertig = messen aus Datei; unterwegs = erwartete Größe aus HEAD.
    private func downloadSizeLabel(for row: StoredDownloadedEpisode) -> String? {
        let bytes = row.fileSizeBytes > 0 ? row.fileSizeBytes : row.expectedSizeBytes
        guard bytes > 0 else { return nil }
        return downloadMegabytesString(bytes: bytes, tilde: row.status != .downloaded)
    }

    private func downloadMegabytesString(bytes: Int64, tilde: Bool) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        let core: String
        if mb >= 100 { core = String(format: "%.0f MB", mb) }
        else { core = String(format: "%.1f MB", mb) }
        return tilde ? "~\(core)" : core
    }

    fileprivate static func formatStorageBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 100 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f MB", mb)
    }
}

private struct DownloadsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var downloadManager: IOSDownloadManager

    @State private var maxPickIndex: Int = 2
    @State private var retentionWeeks: Int = 0

    /// Ab 1 GB in wachsenden Schritten bis 20 GB (Ausgaben ~100–200 MB).
    private let maxOptions: [(label: String, bytes: Int64)] = [
        ("1 GB", 1024 * 1024 * 1024),
        ("2 GB", 2 * 1024 * 1024 * 1024),
        ("3 GB", 3 * 1024 * 1024 * 1024),
        ("5 GB", 5 * 1024 * 1024 * 1024),
        ("8 GB", 8 * 1024 * 1024 * 1024),
        ("12 GB", Int64(12) * 1024 * 1024 * 1024),
        ("16 GB", 16 * 1024 * 1024 * 1024),
        ("20 GB", 20 * 1024 * 1024 * 1024)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Speicher für Downloads", selection: $maxPickIndex) {
                        ForEach(maxOptions.indices, id: \.self) { i in
                            Text(maxOptions[i].label).tag(i)
                        }
                    }
                    .onChange(of: maxPickIndex) { _, _ in saveSettings() }
                } footer: {
                    Text(storageBudgetFooterText)
                }

                Section {
                    Picker("Automatisch löschen nach", selection: $retentionWeeks) {
                        Text("Nie").tag(0)
                        Text("1 Woche").tag(1)
                        Text("2 Wochen").tag(2)
                        Text("3 Wochen").tag(3)
                        Text("4 Wochen").tag(4)
                    }
                    .onChange(of: retentionWeeks) { _, _ in saveSettings() }
                } footer: {
                    Text("Nur abgeschlossene Downloads; die aktuell laufende Wiedergabe wird nicht gelöscht.")
                }
            }
            .navigationTitle("Download-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { loadSettings() }
        }
    }

    private func loadSettings() {
        guard let s = try? StoredDownloadSettings.fetchOrCreate(context: modelContext) else { return }
        if let idx = maxOptions.firstIndex(where: { $0.bytes == s.maxDownloadStorageBytes }) {
            maxPickIndex = idx
        } else {
            let nearest = maxOptions.enumerated().min(by: { abs($0.element.bytes - s.maxDownloadStorageBytes) < abs($1.element.bytes - s.maxDownloadStorageBytes) })?.offset ?? 0
            maxPickIndex = nearest
            s.maxDownloadStorageBytes = maxOptions[nearest].bytes
            try? modelContext.save()
        }
        retentionWeeks = min(4, max(0, s.retentionWeeks))
    }

    private func saveSettings() {
        guard let s = try? StoredDownloadSettings.fetchOrCreate(context: modelContext) else { return }
        s.maxDownloadStorageBytes = maxOptions[min(maxPickIndex, maxOptions.count - 1)].bytes
        s.retentionWeeks = retentionWeeks
        try? modelContext.save()
        Task {
            await downloadManager.runForegroundMaintenance()
        }
    }

    private var storageBudgetFooterText: String {
        let used = (try? IOSDownloadManager.totalDownloadedBytes(context: modelContext)) ?? 0
        let usedStr = DownloadsView.formatStorageBytes(used)
        return "Nur die heruntergeladenen Audiodateien. Aktuell belegt: \(usedStr). Wenn das Limit voll ist, kannst du älteste Sendungen löschen oder das Limit hier erhöhen."
    }
}

#endif
