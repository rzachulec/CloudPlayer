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

// MARK: - macOS 26/27 Liquid Glass Controls

/// Single-source Liquid Glass capsule button styling across the app.
/// Uses native `.glassProminent` / `.glass` on macOS 26+, falling back to capsule-bordered styles on macOS 14–25.
struct LiquidGlassButtonModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            } else {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        } else {
            if prominent {
                content
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            } else {
                content
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// Applies a Liquid Glass interactive capsule surface on macOS 26+ with a translucent capsule fallback.
struct LiquidGlassCapsuleSurface: ViewModifier {
    var interactive: Bool = true

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            content.background(.quaternary.opacity(0.6), in: Capsule())
        }
    }
}

extension View {
    func liquidGlassButton(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonModifier(prominent: prominent))
    }

    func liquidGlassCapsule(interactive: Bool = true) -> some View {
        modifier(LiquidGlassCapsuleSurface(interactive: interactive))
    }
}

/// Capsule inline filter field matching Liquid Glass header controls.
struct LiquidFilterField: View {
    @Binding var text: String
    var prompt: String = "Filter"
    var width: CGFloat = 120

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: width)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .liquidGlassCapsule(interactive: true)
    }
}

/// Concentric capsule segmented icon picker with a sliding thumb for macOS 26/27 Liquid Glass.
struct LiquidIconPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let symbol: (Option) -> String
    let label: (Option) -> String

    @Namespace private var thumbNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        selection = option
                    }
                } label: {
                    Image(systemName: symbol(option))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .frame(width: 28, height: 22)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.14))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "liquidPickerThumb", in: thumbNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(label(option))
            }
        }
        .padding(3)
        .frame(height: 28)
        .liquidGlassCapsule(interactive: false)
    }
}

/// Concentric capsule text segmented picker with a sliding thumb for macOS 26/27 Liquid Glass.
struct LiquidSegmentedPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var compact: Bool = false

    @Namespace private var thumbNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: compact ? 11.5 : 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, compact ? 10 : 13)
                        .frame(height: compact ? 20 : 22)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.14))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "liquidSegmentedThumb", in: thumbNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: compact ? 26 : 28)
        .liquidGlassCapsule(interactive: false)
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
