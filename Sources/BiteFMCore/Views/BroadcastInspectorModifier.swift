import SwiftUI
#if os(macOS)
import AppKit
#endif

/// iPhone: Sheet wird über `selectedItem` gesteuert (`sheet(item:)`), damit SwiftUI die `ArchiveItem`-Identität
/// nicht verliert (vermeidet „Keine Sendung ausgewählt“ bei schnellem Tippen). Schließen: Zieh-Indikator + „Fertig“ unten;
/// der Scroll der `BroadcastDetailView` koordiniert iOS mit dem Sheet (Zieh greift, wenn der Inhalt oben ist).
private struct BroadcastDetailSheetContainer: View {
    let item: ArchiveItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BroadcastDetailView(item: item)
                .navigationTitle("Details")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        Button("Fertig") {
                            dismiss()
                        }
                        .font(.body.weight(.semibold))
                    }
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") {
                            dismiss()
                        }
                    }
                    #endif
                }
        }
    }
}

struct BroadcastInspectorModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedItem: ArchiveItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        Group {
            if horizontalSizeClass == .compact {
                content
                    .sheet(item: $selectedItem) { item in
                        BroadcastDetailSheetContainer(item: item)
                            #if os(iOS)
                            .presentationDragIndicator(.visible)
                            #endif
                    }
                    .onChange(of: selectedItem?.id) { _, newValue in
                        isPresented = newValue != nil
                    }
                    .onChange(of: isPresented) { _, newValue in
                        if !newValue {
                            selectedItem = nil
                        }
                    }
            } else {
                content
                    .inspector(isPresented: $isPresented) {
                        if let item = selectedItem {
                            BroadcastDetailView(item: item)
                                .inspectorColumnWidth(min: 300, ideal: 400, max: 600)
                        } else {
                            ContentUnavailableView("Keine Sendung ausgewählt", systemImage: "info.circle")
                                .inspectorColumnWidth(min: 300, ideal: 400, max: 600)
                        }
                    }
                    .onChange(of: isPresented) { _, newValue in
                        if newValue {
                            ensureMinimumWidth(900)
                        }
                    }
            }
        }
    }

    private func ensureMinimumWidth(_ minWidth: CGFloat) {
        DispatchQueue.main.async {
            #if os(macOS)
            guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow || $0.isVisible }) else { return }
            var frame = window.frame
            if frame.size.width < minWidth {
                let delta = minWidth - frame.size.width
                frame.size.width = minWidth
                frame.origin.x -= delta / 2 // Expand from center
                window.setFrame(frame, display: true, animate: true)
            }
            #endif
        }
    }
}

extension View {
    func broadcastInspector(isPresented: Binding<Bool>, selectedItem: Binding<ArchiveItem?>) -> some View {
        self.modifier(BroadcastInspectorModifier(isPresented: isPresented, selectedItem: selectedItem))
    }
}
