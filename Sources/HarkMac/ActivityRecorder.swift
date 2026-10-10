import AppKit
import HarkCore

/// Notes which app comes to the front and, while Chrome is in front, which site its tab is on, so
/// Hark can spot habits. Names only: never a title, address, text typed or anything copied. It does
/// nothing while learning is off.
@MainActor public final class ActivityRecorder {
    private static let chromeID = "com.google.Chrome"
    private static let siteCheck: TimeInterval = 30

    private let log: ActivityLog
    private let chrome: ChromeTabsSource
    private let isOn: @MainActor () -> Bool
    private var observer: (any NSObjectProtocol)?
    private var timer: Timer?
    private var lastApp = ""
    private var lastAppAt = Date.distantPast
    private var lastSite = ""

    public init(log: ActivityLog, chrome: ChromeTabsSource, isOn: @escaping @MainActor () -> Bool) {
        self.log = log
        self.chrome = chrome
        self.isOn = isOn
    }

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
        let timer = Timer(timeInterval: Self.siteCheck, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSite() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
    }

    private func activated(_ app: NSRunningApplication?) {
        guard isOn(), let app, app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let name = app.localizedName
        else { return }
        // Switching straight back and forth is one visit, not many.
        let now = Date()
        if name != lastApp || now.timeIntervalSince(lastAppAt) > 5 {
            log.append(ActivityEvent(at: now, kind: .app, name: name))
        }
        lastApp = name
        lastAppAt = now
        // Coming back to Chrome counts as a new visit to whatever site is showing.
        lastSite = ""
        if app.bundleIdentifier == Self.chromeID {
            // Give Chrome a moment to show the tab that was in front.
            Task { try? await Task.sleep(for: .seconds(1.5)); checkSite() }
        }
    }

    private func checkSite() {
        guard isOn(), NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.chromeID else { return }
        Task {
            guard let host = await chrome.frontSite(), host != lastSite else { return }
            lastSite = host
            log.append(ActivityEvent(at: Date(), kind: .site, name: host))
        }
    }
}
