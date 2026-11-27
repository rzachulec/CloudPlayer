import AppKit
import SwiftUI

extension Notification.Name {
    static let cpFocusSearch = Notification.Name("cpFocusSearch")
    static let cpToggleSidebar = Notification.Name("cpToggleSidebar")
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var active = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

func formatTime(_ t: Double) -> String {
    guard t.isFinite, t > 0 else { return "0:00" }
    let total = Int(t.rounded())
    return total >= 3600
        ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        : String(format: "%d:%02d", total / 60, total % 60)
}

/// Native NSSearchField for the toolbar: Return searches, ⌘F (Edit ▸ Search) focuses it.
struct ToolbarSearchField: NSViewRepresentable {
    let prompt: String
    let onSubmit: (String) -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsWholeSearchString = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        context.coordinator.observe(field)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSubmit: onSubmit) }

    final class Coordinator: NSObject {
        var onSubmit: (String) -> Void
        private var token: NSObjectProtocol?
        init(onSubmit: @escaping (String) -> Void) { self.onSubmit = onSubmit }

        @objc func submit(_ sender: NSSearchField) {
            let q = sender.stringValue.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { onSubmit(q) }
        }

        func observe(_ field: NSSearchField) {
            token = NotificationCenter.default.addObserver(
                forName: .cpFocusSearch,
                object: nil,
                queue: .main
            ) { [weak field] _ in
                guard let field else { return }
                field.window?.makeFirstResponder(field)
            }
        }

        deinit { token.map(NotificationCenter.default.removeObserver) }
    }
}
