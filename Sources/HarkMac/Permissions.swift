import AppKit
import ApplicationServices
import AVFoundation

public enum Permission: String, Sendable, CaseIterable {
    case microphone, accessibility, automation
}

public enum PermissionStatus: String, Sendable {
    case granted, denied, notAsked
}

public enum Permissions {
    public static func status(_ permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .accessibility:
            // macOS does not say whether the user refused or was never asked.
            AXIsProcessTrusted() ? .granted : .notAsked
        case .automation:
            chromeAutomationStatus()
        }
    }

    public static func openSettings(for permission: Permission) {
        let pane = switch permission {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .automation: "Privacy_Automation"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func chromeAutomationStatus() -> PermissionStatus {
        let chrome = NSAppleEventDescriptor(bundleIdentifier: "com.google.Chrome")
        let status = AEDeterminePermissionToAutomateTarget(chrome.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        // Covers "would ask" and "Chrome is not running", when macOS cannot answer yet.
        default: return .notAsked
        }
    }
}
