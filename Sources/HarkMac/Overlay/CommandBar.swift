import AppKit
import SwiftUI

/// A small bar for typing a command instead of speaking it. Like the overlay it takes the
/// keyboard without bringing Hark to the front, so the command still acts on the app the user
/// was in.
@MainActor public final class CommandBar {
    /// Called with what the user typed when they press Return.
    public var onSubmit: ((String) -> Void)?

    private static let size = NSSize(width: 600, height: 132)
    private static let remembered = 20

    private let panel: CommandBarPanel
    private let model = CommandBarModel()

    public init() {
        panel = CommandBarPanel(size: Self.size)
        let host = NSHostingView(rootView: CommandBarView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.onResignKey = { [weak self] in self?.hide() }
        model.onSubmit = { [weak self] text in self?.submit(text) }
        model.onCancel = { [weak self] in self?.hide() }
    }

    public var isShown: Bool { panel.isVisible }

    public func show() {
        model.text = ""
        model.recall = nil
        model.focusRequests += 1
        panel.setFrameOrigin(originOnMouseScreen())
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel.orderOut(nil)
    }

    private func submit(_ text: String) {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        hide()
        guard !command.isEmpty else { return }
        model.earlier.removeAll { $0 == command }
        model.earlier.append(command)
        model.earlier = Array(model.earlier.suffix(Self.remembered))
        onSubmit?(command)
    }

    /// A third of the way down the screen the mouse is on, where a launcher is expected.
    private func originOnMouseScreen() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return .zero }
        return NSPoint(x: area.midX - Self.size.width / 2, y: area.minY + area.height * 0.62)
    }
}

@MainActor @Observable final class CommandBarModel {
    var text = ""
    /// Commands typed before, oldest first, for the up and down arrows.
    var earlier: [String] = []
    var recall: Int?
    var focusRequests = 0
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    func step(_ direction: Int) {
        guard !earlier.isEmpty else { return }
        let next = (recall ?? earlier.count) + direction
        guard next >= 0 else { return }
        if next >= earlier.count {
            recall = nil
            text = ""
        } else {
            recall = next
            text = earlier[next]
        }
    }
}

private struct CommandBarView: View {
    @Bindable var model: CommandBarModel
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Type a command", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .accessibilityLabel("Command")
                    .onSubmit { model.onSubmit?(model.text) }
                    .onKeyPress(.upArrow) {
                        model.step(-1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.step(1)
                        return .handled
                    }
            }
            Text("Return to run it, Esc to close, up arrow for earlier commands")
                .font(OverlayStyle.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 520, alignment: .leading)
        .background(CommandBarMaterial().clipShape(shape))
        .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { model.onCancel?() }
        .onChange(of: model.focusRequests, initial: true) { focused = true }
    }
}

private struct CommandBarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Takes the keyboard without activating Hark, the way a launcher does.
private final class CommandBarPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
