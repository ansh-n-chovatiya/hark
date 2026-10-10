import Testing

@testable import HarkCore

@Suite struct WindowLayoutTests {
    @Test func twoAppsSideBySide() {
        let moves = WindowLayout.request(in: "put VS Code on the left and Chrome on the right")
        #expect(moves == [WindowMove(app: "vs code", place: .left), WindowMove(app: "chrome", place: .right)])
        #expect(WindowLayout.request(in: "Chrome on the left and the editor on the right")?.count == 2)
    }

    @Test func oneWindowToAPlace() {
        #expect(WindowLayout.request(in: "move Slack to the right half") == [WindowMove(app: "slack", place: .right)])
        #expect(WindowLayout.request(in: "snap this window to the left") == [WindowMove(app: nil, place: .left)])
        #expect(WindowLayout.request(in: "put Chrome in the top left corner") == [WindowMove(app: "chrome", place: .topLeft)])
        #expect(WindowLayout.request(in: "put Safari on the right third") == [WindowMove(app: "safari", place: .rightThird)])
        #expect(WindowLayout.request(in: "centre this window") == [WindowMove(app: nil, place: .centre)])
    }

    @Test func fullSize() {
        #expect(WindowLayout.request(in: "make this window full size") == [WindowMove(app: nil, place: .full)])
        #expect(WindowLayout.request(in: "maximize Chrome") == [WindowMove(app: "chrome", place: .full)])
        #expect(WindowLayout.request(in: "full screen") == [WindowMove(app: nil, place: .full)])
    }

    @Test func otherCommandsAreLeftAlone() {
        #expect(WindowLayout.request(in: "open slack") == nil)
        #expect(WindowLayout.request(in: "switch to the left tab of my project") == nil)
        #expect(WindowLayout.request(in: "put the kettle on") == nil)
        #expect(WindowLayout.request(in: "") == nil)
        #expect(WindowLayout.request(in: "paste the thing I copied on the right") == nil)
    }
}
