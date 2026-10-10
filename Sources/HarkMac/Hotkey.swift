import CoreGraphics
import Foundation

public enum HotkeyError: LocalizedError, Sendable, Equatable {
    case accessibilityNotGranted
    case unknownKey(String)
    case tapUnavailable

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            "Hark needs the Accessibility permission to notice its key. "
                + "Turn Hark on in System Settings > Privacy & Security > Accessibility, then start it again."
        case .unknownKey(let key):
            "\"\(key)\" is not a key Hark can listen for. Use one of: \(Trigger.names.joined(separator: ", "))."
        case .tapUnavailable:
            "macOS refused to let Hark listen for its key. Check that Hark is turned on under both "
                + "Accessibility and Input Monitoring in System Settings > Privacy & Security."
        }
    }
}

/// Callbacks arrive in order on a private serial queue, never on the main thread.
public final class Hotkey {
    private let key: String
    private let onDown: @Sendable () -> Void
    private let onUp: @Sendable () -> Void
    private let onCancel: @Sendable () -> Void
    private var tap: EventTap?

    public init(key: String, onDown: @escaping @Sendable () -> Void, onUp: @escaping @Sendable () -> Void,
                onCancel: @escaping @Sendable () -> Void) {
        self.key = key
        self.onDown = onDown
        self.onUp = onUp
        self.onCancel = onCancel
    }

    deinit {
        tap?.stop()
    }

    public func start() throws {
        guard tap == nil else { return }
        guard let trigger = Trigger(name: key) else { throw HotkeyError.unknownKey(key) }
        guard Permissions.status(.accessibility) == .granted else { throw HotkeyError.accessibilityNotGranted }
        tap = try EventTap(trigger: trigger, onDown: onDown, onUp: onUp, onCancel: onCancel)
    }

    public func stop() {
        tap?.stop()
        tap = nil
    }
}

private struct Trigger {
    let keyCode: CGKeyCode
    /// Set only for modifier keys: the bit in the event flags that belongs to this one physical key.
    let ownFlag: UInt64?
    /// The left-or-right flag the key shares with its twin, so the twin does not count as a second key.
    let sharedFlag: CGEventFlags

    var isModifier: Bool { ownFlag != nil }

    // The per-key bits are the NX_DEVICE*KEYMASK values from IOKit's IOLLEvent.h.
    private static let modifiers: [String: (CGKeyCode, UInt64, CGEventFlags)] = [
        "rightoption": (61, 0x40, .maskAlternate),
        "leftoption": (58, 0x20, .maskAlternate),
        "rightcommand": (54, 0x10, .maskCommand),
        "leftcommand": (55, 0x08, .maskCommand),
        "rightcontrol": (62, 0x2000, .maskControl),
        "leftcontrol": (59, 0x01, .maskControl),
        "rightshift": (60, 0x04, .maskShift),
        "leftshift": (56, 0x02, .maskShift),
        // fn (the Globe key on newer Macs). Its flag is the one bit macOS gives it; there is no per-side bit.
        "fn": (63, 0x800000, .maskSecondaryFn),
    ]

    private static let plainKeys: [String: CGKeyCode] = [
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]

    static let names = ["fn", "rightOption", "leftOption", "rightCommand", "leftCommand", "rightControl", "leftControl",
                        "rightShift", "leftShift", "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20"]

    init?(name: String) {
        let name = name.lowercased()
        if let (keyCode, ownFlag, sharedFlag) = Self.modifiers[name] {
            self.keyCode = keyCode
            self.ownFlag = ownFlag
            self.sharedFlag = sharedFlag
        } else if let keyCode = Self.plainKeys[name] {
            self.keyCode = keyCode
            self.ownFlag = nil
            self.sharedFlag = []
        } else {
            return nil
        }
    }
}

/// `hold` is touched only on the tap thread; `port` and `runLoop` are fixed before `init` returns.
private final class EventTap: @unchecked Sendable {
    private enum Hold {
        case idle
        case active
        /// The key is down but this press is not for Hark: it is part of a shortcut.
        case spoiled
    }

    private static let anyModifier: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand,
                                                    .maskSecondaryFn]

    private let trigger: Trigger
    private let onDown: @Sendable () -> Void
    private let onUp: @Sendable () -> Void
    private let onCancel: @Sendable () -> Void
    private let callbacks = DispatchQueue(label: "hark.hotkey.callbacks", qos: .userInteractive)
    private var hold = Hold.idle
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?

    init(trigger: Trigger, onDown: @escaping @Sendable () -> Void, onUp: @escaping @Sendable () -> Void,
         onCancel: @escaping @Sendable () -> Void) throws {
        self.trigger = trigger
        self.onDown = onDown
        self.onUp = onUp
        self.onCancel = onCancel

        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // Listen-only: the tap cannot swallow or alter any key, fn included.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { throw HotkeyError.tapUnavailable }
        self.port = port

        // Its own thread, so a busy main thread can neither delay the callbacks nor make macOS
        // disable the tap for answering too slowly.
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, self.port, 0), .commonModes)
            resume()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "hark.hotkey.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stop() {
        guard let port, let runLoop else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        CFRunLoopStop(runLoop)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            resumeAfterDisable()
        case .flagsChanged where trigger.isModifier:
            modifierChanged(event)
        case .keyDown where trigger.isModifier:
            spoilHold()
        case .keyDown where isTriggerKey(event) && event.getIntegerValueField(.keyboardEventAutorepeat) == 0:
            begin()
        case .keyUp where !trigger.isModifier && isTriggerKey(event):
            end()
        default:
            break
        }
    }

    private func modifierChanged(_ event: CGEvent) {
        guard isTriggerKey(event) else {
            spoilHold()
            return
        }
        guard let ownFlag = trigger.ownFlag, event.flags.rawValue & ownFlag != 0 else {
            end()
            return
        }
        guard hold == .idle else { return }
        let othersHeld = !event.flags.intersection(Self.anyModifier).subtracting(trigger.sharedFlag).isEmpty
        if othersHeld {
            hold = .spoiled
        } else {
            begin()
        }
    }

    private func isTriggerKey(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == Int64(trigger.keyCode)
    }

    private func begin() {
        guard hold == .idle else { return }
        hold = .active
        callbacks.async(execute: onDown)
    }

    private func end() {
        if hold == .active { callbacks.async(execute: onUp) }
        hold = .idle
    }

    private func spoilHold() {
        guard hold == .active else { return }
        hold = .spoiled
        callbacks.async(execute: onCancel)
    }

    private func resume() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func resumeAfterDisable() {
        resume()
        // The release may have been missed while the tap was off; without this the hold never ends.
        guard hold != .idle, !CGEventSource.keyState(.combinedSessionState, key: trigger.keyCode) else { return }
        if hold == .active { callbacks.async(execute: onCancel) }
        hold = .idle
    }
}
