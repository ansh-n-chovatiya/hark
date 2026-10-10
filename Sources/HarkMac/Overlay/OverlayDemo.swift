import Foundation
import HarkCore

extension Overlay {
    /// Shows every state in turn so the panel can be checked by eye without a microphone.
    public func runDemo() {
        let callerOnPick = onPick
        onPick = { [weak self] number in
            self?.show(.result("You picked \(number)"))
        }

        Task { [weak self] in
            for (state, stay) in Self.demoSteps {
                guard let self else { return }
                self.show(state)
                try? await Task.sleep(for: stay)
            }
            self?.show(.hidden)
            self?.onPick = callerOnPick
        }
    }

    private static var demoSteps: [(OverlayState, Duration)] {
        let sample = [
            Item(id: "tab:1", kind: .tab, title: "Render logs", detail: "dashboard.render.com", owner: "Google Chrome"),
            Item(id: "tab:2", kind: .tab, title: "Render deploys", detail: "dashboard.render.com", owner: "Google Chrome"),
            Item(id: "window:1", kind: .window, title: "backend", detail: "main.py", owner: "Visual Studio Code"),
            Item(id: "file:1", kind: .file, title: "render.yaml", detail: "~/Projects/backend", owner: "Finder"),
            Item(id: "app:1", kind: .app, title: "Terminal"),
        ]
        let matches = sample.map { Match(item: $0, score: 0.8) }

        return [
            (.listening, .seconds(3)),
            (.hearing("switch to"), .seconds(1)),
            (.hearing("switch to the render logs tab"), .seconds(2)),
            (.result("Switched to Render logs"), .seconds(3)),
            (.choices(matches), .seconds(8)),
            (.confirm("Close 4 duplicate tabs?"), .seconds(8)),
            (.error("Did not catch that. Try again."), .seconds(4)),
            (.listening, .seconds(4)),
        ]
    }
}
