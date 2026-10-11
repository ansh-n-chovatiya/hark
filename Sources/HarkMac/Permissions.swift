import AppKit
import ApplicationServices
import AVFoundation

public enum Permission: String, Sendable, CaseIterable {
    case microphone, accessibility, automation
}

public enum PermissionStatus: String, Sendable {
    case granted, denied, notAsked
    /// macOS cannot say until the app is running, as with Chrome while it is closed.
    case unknown
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
        // macOS only answers for an app that is open ("process not found" otherwise), and that is not a no.
        guard let browser = Browsers.scriptable.first(where: {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }) else { return .unknown }
        let target = NSAppleEventDescriptor(bundleIdentifier: browser.bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .unknown
        // "Would ask": Hark has not been allowed yet.
        default: return .notAsked
        }
    }
}
