import Testing

@testable import HarkCore

@Suite struct CommandSandboxTests {
    @Test func readOnlyDeniesWritesAndNetwork() {
        let profile = CommandSandbox.profile(allowingChanges: false)
        #expect(profile.contains("(deny file-write*)"))
        #expect(profile.contains("(deny network*)"))
    }

    @Test func allowingChangesStillDeniesDeletingAndMoving() {
        let profile = CommandSandbox.profile(allowingChanges: true)
        #expect(profile.contains("(deny file-write-unlink)"))
        #expect(!profile.contains("(deny network*)"))
    }

    @Test func theCommandIsRunUnderTheProfile() {
        let run = CommandSandbox.arguments(running: "ls", allowingChanges: false)
        #expect(run.executable == "/usr/bin/sandbox-exec")
        #expect(run.arguments.suffix(3) == ["/bin/zsh", "-lc", "ls"])
    }
}
