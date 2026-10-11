import AppKit
import SwiftUI

public enum DictationState: Sendable, Equatable {
    case hidden, listening, handsFree, typing, typed(Int), copied(Int), done(String), error(String)
}

/// A small pill that says dictation is on, with a waveform that follows the voice and a cancel
/// button. It is kept small, starts in the top-right corner under the menu bar, and can be dragged
/// anywhere: prompts are written in the middle and at the bottom of the screen, and the words being
/// typed have to stay in view. Where the user puts it is remembered.
@MainActor public final class DictationIndicator {
    /// Called when the cancel button is pressed.
    public var onCancel: (() -> Void)?
    /// Called when the stop button of a hands-free dictation is pressed.
    public var onFinish: (() -> Void)?

    private static let margin: CGFloat = 12
    private static let doneStay: Duration = .milliseconds(1200)
    private static let errorStay: Duration = .milliseconds(4000)
    /// Long enough to read, as it asks for something to be done.
    private static let copiedStay: Duration = .milliseconds(5000)
    private static let offsetKey = "dictationPillOffset"

    private let panel: NSPanel
    private let host: NSHostingView<DictationPill>
    private let model = DictationModel()
    private var hideTask: Task<Void, Never>?
    private var isPlacing = false
    private var moveObserver: (any NSObjectProtocol)?

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 40),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        host = NSHostingView(rootView: DictationPill(model: model))
        // The panel is sized from the pill, so the view has to report its own size.
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        model.onCancel = { [weak self] in self?.onCancel?() }
        model.onFinish = { [weak self] in self?.onFinish?() }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.remember() }
        }
    }

    public func show(_ state: DictationState) {
        hideTask?.cancel()
        hideTask = nil
        guard state != .hidden else {
            panel.orderOut(nil)
            model.state = .hidden
            return
        }
        model.state = state
        place()
        if !panel.isVisible {
            // A short fade so it settles in instead of popping.
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
        switch state {
        case .typed, .done: hide(after: Self.doneStay)
        case .copied: hide(after: Self.copiedStay)
        case .error: hide(after: Self.errorStay)
        default: break
        }
    }

    private func hide(after delay: Duration) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.show(.hidden)
        }
    }

    /// Sizes the panel to the pill and keeps its top-right corner where it is (or where it was
    /// left last time), so a state with more text grows to the left.
    private func place() {
        isPlacing = true
        defer { isPlacing = false }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        // Never a window with no size: it would be there and invisible.
        if size.width < 40 || size.height < 20 { size = NSSize(width: 120, height: 44) }
        let corner: NSPoint
        if panel.isVisible {
            corner = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        } else {
            let area = screenArea()
            let offset = (UserDefaults.standard.array(forKey: Self.offsetKey) as? [Double]) ?? [-Self.margin, -Self.margin]
            corner = NSPoint(
                x: min(max(area.maxX + CGFloat(offset[0]), area.minX + size.width), area.maxX),
                y: min(max(area.maxY + CGFloat(offset[1]), area.minY + size.height), area.maxY))
        }
        panel.setFrame(NSRect(x: corner.x - size.width, y: corner.y - size.height, width: size.width, height: size.height), display: true)
    }

    /// Saves where the user dropped the pill, as a distance from the top-right of the screen it is on.
    private func remember() {
        guard !isPlacing, panel.isVisible else { return }
        let area = screenArea(containing: panel.frame)
        UserDefaults.standard.set(
            [Double(panel.frame.maxX - area.maxX), Double(panel.frame.maxY - area.maxY)], forKey: Self.offsetKey)
    }

    private func screenArea(containing rect: NSRect? = nil) -> NSRect {
        let point = rect.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }
}

@MainActor @Observable final class DictationModel {
    var state: DictationState = .hidden
    var onCancel: (() -> Void)?
    var onFinish: (() -> Void)?
}

struct DictationPill: View {
    let model: DictationModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.state != .hidden {
            HStack(spacing: 12) {
                content
            }
            .padding(.leading, 16)
            .padding(.trailing, trailing)
            .frame(minHeight: 40)
            // A fixed dark pill reads the same over any window, light or dark, where a see-through
            // one took on the colour of whatever was behind it.
            .background(Capsule().fill(Color(white: 0.09, opacity: 0.94)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .environment(\.colorScheme, .dark)
            .padding(10)
            .fixedSize()
        }
    }

    /// Less room on the right when the cancel button sits there.
    private var trailing: CGFloat { model.state == .listening || model.state == .handsFree ? 8 : 16 }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .listening:
            LevelBars(animates: !reduceMotion)
                .frame(width: 52, height: 22)
                .accessibilityLabel("Dictating")
            CancelButton { model.onCancel?() }
        case .handsFree:
            LevelBars(animates: !reduceMotion)
                .frame(width: 44, height: 22)
                .accessibilityLabel("Dictating, hands-free")
            StopButton { model.onFinish?() }
            CancelButton { model.onCancel?() }
        case .typing:
            ProgressView().controlSize(.small).accessibilityHidden(true)
            label("Typing\u{2026}")
        case .typed(let words):
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.green)
                .accessibilityHidden(true)
            label("Typed \(words) \(words == 1 ? "word" : "words")")
        case .done(let message):
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.green)
                .accessibilityHidden(true)
            label(message).frame(maxWidth: 260, alignment: .leading).padding(.vertical, 8)
        case .copied(let words):
            Image(systemName: "doc.on.clipboard.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
            label("No text box. \(words) \(words == 1 ? "word" : "words") copied: press \u{2318}V to paste")
                .frame(maxWidth: 260, alignment: .leading).padding(.vertical, 8)
        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundStyle(.orange)
                .accessibilityHidden(true)
            label(message).frame(maxWidth: 260, alignment: .leading).padding(.vertical, 8)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Finishes a hands-free dictation and types what was said.
private struct StopButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.red.opacity(isHovered ? 1 : 0.85)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Finish and type")
        .accessibilityLabel("Finish dictation and type")
    }
}

private struct CancelButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(isHovered ? 1 : 0.75))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(isHovered ? 0.24 : 0.13)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Cancel")
        .accessibilityLabel("Cancel dictation")
    }
}

/// Bars that rise and fall with the voice. Drawn with layers and a timer rather than SwiftUI
/// animation, for the same reason the listening pulse is: a redraw on every frame would wait on a
/// busy main thread and delay the key's release.
private struct LevelBars: NSViewRepresentable {
    let animates: Bool

    func makeNSView(context: Context) -> LevelBarsView { LevelBarsView() }

    func updateNSView(_ view: LevelBarsView, context: Context) { view.animates = animates }
}

private final class LevelBarsView: NSView {
    private static let count = 9
    /// Taller in the middle, so it reads as a voice and not a meter.
    private static let weights: [CGFloat] = [0.35, 0.55, 0.75, 0.92, 1.0, 0.92, 0.75, 0.55, 0.35]
    private static let barWidth: CGFloat = 3.5
    private static let shortest: CGFloat = 3

    var animates = true
    private var bars: [CALayer] = []
    private var heights = [CGFloat](repeating: 0, count: LevelBarsView.count)
    private var timer: Timer?
    private var phase: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<Self.count {
            let bar = CALayer()
            bar.cornerRadius = Self.barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
    }

    override func layout() {
        super.layout()
        tick()
    }

    private func recolor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for bar in bars { bar.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor }
        }
    }

    private func tick() {
        recolor()
        let level = animates ? CGFloat(MicrophoneLevel.current) : 0.5
        phase += 0.35
        let step = (bounds.width - Self.barWidth) / CGFloat(Self.count - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<Self.count {
            // A small ripple keeps the bars alive in silence, so it never looks frozen.
            let ripple = animates ? 0.3 + 0.18 * sin(phase + CGFloat(index) * 0.9) : 0.35
            let target = Self.shortest + (bounds.height - Self.shortest) * min(1, (level + ripple) * Self.weights[index])
            heights[index] += (target - heights[index]) * 0.5
            bars[index].frame = CGRect(
                x: CGFloat(index) * step, y: (bounds.height - heights[index]) / 2,
                width: Self.barWidth, height: heights[index])
        }
        CATransaction.commit()
    }
}
