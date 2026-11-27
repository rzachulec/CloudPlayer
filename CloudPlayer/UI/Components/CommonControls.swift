import AppKit
import Observation
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

// MARK: - Properly Anchored Native macOS Share Picker

/// Presents `NSSharingServicePicker` anchored at the current mouse cursor in the active window
/// (fixes SwiftUI `ShareLink` in `.contextMenu` falling back to top-center of the window).
@MainActor
func presentSharePickerAtCursor(url: URL) {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
          let contentView = window.contentView else { return }
    let screenPt = NSEvent.mouseLocation
    let windowPt = window.convertPoint(fromScreen: screenPt)
    let viewPt = contentView.convert(windowPt, from: nil)
    let rect = NSRect(x: viewPt.x, y: viewPt.y, width: 1, height: 1)
    let picker = NSSharingServicePicker(items: [url])
    picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
}

@MainActor
private final class ShareAnchorBox {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let box: ShareAnchorBox
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        box.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

/// Inline `Share ▸` submenu for `.contextMenu` that keeps the parent context menu open while
/// browsing and invoking native macOS sharing services right beside the menu item.
struct ContextShareSubmenu: View {
    let url: URL
    var onCopied: (() -> Void)?

    var body: some View {
        Menu("Share", systemImage: "square.and.arrow.up") {
            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                onCopied?()
            }

            let services = NSSharingService.sharingServices(forItems: [url])
            if !services.isEmpty {
                Divider()
                ForEach(services, id: \.title) { service in
                    Button {
                        service.perform(withItems: [url])
                    } label: {
                        Label {
                            Text(service.menuItemTitle)
                        } icon: {
                            Image(nsImage: service.image)
                        }
                    }
                }
            }
        }
    }
}

/// Liquid Glass Share button that anchors `NSSharingServicePicker` directly to the button itself.
struct NativeShareButton: View {
    let url: URL
    var title: String = "Share"

    @State private var anchor = ShareAnchorBox()

    var body: some View {
        Button {
            if let view = anchor.view {
                NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            } else {
                presentSharePickerAtCursor(url: url)
            }
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .background(ShareAnchorView(box: anchor))
    }
}

// MARK: - Horizontal Scroll with Liquid Glass Navigation Chevrons

@MainActor
@Observable
private final class HorizontalScrollController {
    private(set) var canScrollLeft = false
    private(set) var canScrollRight = false

    weak var scrollView: NSScrollView? {
        didSet {
            guard scrollView !== oldValue else { return }
            attachObservers()
            updateScrollState()
        }
    }

    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    deinit {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func attachObservers() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
        guard let sv = scrollView else { return }

        sv.contentView.postsBoundsChangedNotifications = true
        let boundsObs = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: sv.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateScrollState() }
        }
        observers.append(boundsObs)

        if let doc = sv.documentView {
            doc.postsFrameChangedNotifications = true
            let frameObs = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: doc,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.updateScrollState() }
            }
            observers.append(frameObs)
        }
    }

    func updateScrollState() {
        guard let sv = scrollView, let doc = sv.documentView else {
            canScrollLeft = false
            canScrollRight = false
            return
        }
        let visibleWidth = sv.contentView.bounds.width
        let contentWidth = doc.bounds.width
        let offsetX = sv.contentView.bounds.origin.x
        let maxOffset = max(0, contentWidth - visibleWidth)

        let left = offsetX > 4
        let right = (maxOffset - offsetX) > 4
        if canScrollLeft != left { canScrollLeft = left }
        if canScrollRight != right { canScrollRight = right }
    }

    func scroll(forward: Bool) {
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let clip = sv.contentView
        let visibleWidth = clip.bounds.width
        let maxOffset = max(0, doc.bounds.width - visibleWidth)
        let step = max(180, visibleWidth * 0.78)
        let currentX = clip.bounds.origin.x
        let targetX = forward
            ? min(maxOffset, currentX + step)
            : max(0, currentX - step)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(NSPoint(x: targetX, y: clip.bounds.origin.y))
        } completionHandler: { [weak self] in
            Task { @MainActor in
                sv.reflectScrolledClipView(clip)
                self?.updateScrollState()
            }
        }
    }
}

private struct HorizontalScrollProbe: NSViewRepresentable {
    let controller: HorizontalScrollController

    func makeNSView(context: Context) -> NSView {
        let view = ProbeNSView()
        view.onAttach = { [weak controller] sv in
            controller?.scrollView = sv
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let sv = nsView.enclosingScrollView {
            controller.scrollView = sv
            controller.updateScrollState()
        }
    }

    private final class ProbeNSView: NSView {
        var onAttach: ((NSScrollView?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onAttach?(enclosingScrollView)
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onAttach?(enclosingScrollView)
        }
    }
}

private struct ShelfChevronButton: View {
    let symbol: String
    let compact: Bool
    let help: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let diameter: CGFloat = compact ? 24 : 34
        let iconSize: CGFloat = compact ? 10 : 13

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .modifier(CircleGlassSurface())
                .scaleEffect(hovered ? 1.07 : 1.0)
                .animation(.easeOut(duration: 0.14), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

private struct CircleGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        }
    }
}

/// Horizontal `ScrollView` with hover-revealed Liquid Glass left/right scroll buttons that
/// smoothly page through shelves and hide automatically at the scroll boundaries.
struct LiquidHorizontalScroll<Content: View>: View {
    var compact: Bool = false
    @ViewBuilder let content: () -> Content

    @State private var controller = HorizontalScrollController()
    @State private var isHovered = false

    var body: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                content()
                    .background(HorizontalScrollProbe(controller: controller))
            }

            HStack {
                if controller.canScrollLeft {
                    ShelfChevronButton(symbol: "chevron.left", compact: compact, help: "Scroll Left") {
                        controller.scroll(forward: false)
                    }
                    .padding(.leading, compact ? 2 : 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer(minLength: 0)

                if controller.canScrollRight {
                    ShelfChevronButton(symbol: "chevron.right", compact: compact, help: "Scroll Right") {
                        controller.scroll(forward: true)
                    }
                    .padding(.trailing, compact ? 2 : 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.easeOut(duration: 0.16), value: controller.canScrollLeft)
            .animation(.easeOut(duration: 0.16), value: controller.canScrollRight)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering { controller.updateScrollState() }
        }
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
