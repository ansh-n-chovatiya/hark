import AppKit
import HarkCore
import SwiftUI

public enum OverlayState: Sendable {
    case hidden, listening, hearing(String), working(String), result(String), answer(String),
         choices([Match]), confirm(String), error(String)
}

@MainActor public final class Overlay {
    public var onPick: ((Int) -> Void)?

    static let maxChoices = 5

    private static let panelSize = NSSize(width: 520, height: 440)
    private static let bottomGap: CGFloat = 48
    private static let fadeIn: TimeInterval = 0.12
    private static let fadeOut: TimeInterval = 0.2
    private static let resultStay: Duration = .milliseconds(1500)
    private static let errorStay: Duration = .milliseconds(4000)
    /// An answer is something to read, not a passing confirmation.
    private static let answerStay: Duration = .milliseconds(8000)

    private let panel: OverlayPanel
    private let model = OverlayModel()
    private var showCount = 0
    private var pickableCount = 0
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var autoHide: Task<Void, Never>?
    private var orderOut: Task<Void, Never>?

    public init() {
        panel = OverlayPanel(size: Self.panelSize)
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    public func show(_ state: OverlayState) {
        showCount += 1
        autoHide?.cancel()
        autoHide = nil

        switch state {
        case .hidden:
            setPickable(0)
            fadeAway()
        case .listening, .hearing, .working:
            setPickable(0)
            present(state)
        case .result:
            setPickable(0)
            present(state)
            hide(after: Self.resultStay)
        case .error:
            setPickable(0)
            present(state)
            hide(after: Self.errorStay)
        case .answer:
            setPickable(0)
            present(state)
            hide(after: Self.answerStay)
        case .choices(let matches):
            guard !matches.isEmpty else {
                setPickable(0)
                fadeAway()
                return
            }
            present(state)
            setPickable(min(matches.count, Self.maxChoices))
        case .confirm:
            present(state)
            setPickable(2)
        }
    }

    private func present(_ state: OverlayState) {
        orderOut?.cancel()
        orderOut = nil
        model.state = state
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrameOrigin(originOnMouseScreen())
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }
    }

    private func fadeAway() {
        guard panel.isVisible, orderOut == nil else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut
            panel.animator().alphaValue = 0
        }
        orderOut = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            guard !Task.isCancelled, let self else { return }
            self.panel.orderOut(nil)
            self.model.state = .hidden
            self.orderOut = nil
        }
    }

    private func hide(after delay: Duration) {
        autoHide = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.show(.hidden)
        }
    }

    private func originOnMouseScreen() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return .zero }
        return NSPoint(x: area.midX - Self.panelSize.width / 2, y: area.minY + Self.bottomGap)
    }

    // MARK: Number keys

    private func setPickable(_ count: Int) {
        pickableCount = count
        if count > 0 {
            startKeyMonitors()
        } else {
            stopKeyMonitors()
        }
    }

    private func startKeyMonitors() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handleKey(event.keyCode, flags: event.modifierFlags, isRepeat: event.isARepeat)
                else { return event }
                return nil
            }
        }
        guard keyTap == nil, globalMonitor == nil else { return }
        if !startKeyTap() {
            // Without the tap the pick still works, but the key also reaches the app in front.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                _ = self?.handleKey(event.keyCode, flags: event.modifierFlags, isRepeat: event.isARepeat)
            }
        }
    }

    /// A tap can swallow the key, so picking "2" does not also type a 2 into the app in front.
    private func startKeyTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: overlayKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        keyTapSource = source
        return true
    }

    private func stopKeyMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes)
        }
        localMonitor = nil
        globalMonitor = nil
        keyTap = nil
        keyTapSource = nil
    }

    fileprivate func handleTapped(_ type: CGEventType, keyCode: UInt16, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return false
        }
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        return handleKey(keyCode, flags: modifiers, isRepeat: isRepeat)
    }

    private func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard pickableCount > 0, !isRepeat else { return false }
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard flags.isDisjoint(with: shortcutModifiers) else { return false }

        if keyCode == KeyCode.escape {
            show(.hidden)
            return true
        }
        guard let number = KeyCode.number(for: keyCode), number <= pickableCount else { return false }

        setPickable(0)
        let countBeforePick = showCount
        onPick?(number)
        // The caller usually answers with a result; hide only when it showed nothing.
        if showCount == countBeforePick {
            show(.hidden)
        }
        return true
    }
}

// The tap's run loop source is on the main run loop, so this always runs on the main thread.
private func overlayKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let overlayAddress = UInt(bitPattern: userInfo)
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let swallowed = MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: overlayAddress) else { return false }
        return Unmanaged<Overlay>.fromOpaque(pointer).takeUnretainedValue()
            .handleTapped(type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
    }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}

@MainActor @Observable final class OverlayModel {
    var state: OverlayState = .hidden
}

private enum KeyCode {
    static let escape: UInt16 = 53

    // Key codes rather than characters, so the number row works on layouts where digits need Shift.
    private static let numberRow: [UInt16] = [18, 19, 20, 21, 23]
    private static let keypad: [UInt16] = [83, 84, 85, 86, 87]

    static func number(for keyCode: UInt16) -> Int? {
        guard let index = numberRow.firstIndex(of: keyCode) ?? keypad.firstIndex(of: keyCode) else { return nil }
        return index + 1
    }
}

private final class OverlayPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // The panel is larger than the card it draws, so clicks must fall through to what is behind.
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
