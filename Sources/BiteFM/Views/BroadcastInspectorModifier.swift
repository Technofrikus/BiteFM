import SwiftUI

struct BroadcastInspectorModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedItem: ArchiveItem?
    
    func body(content: Content) -> some View {
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
            .onChange(of: isPresented) { oldValue, newValue in
                if newValue {
                    ensureMinimumWidth(900)
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
