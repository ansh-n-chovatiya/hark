import Testing

@testable import HarkCore

@Suite struct SystemCommandTests {
    @Test func volumeTakesALevel() {
        #expect(SystemCommand.request(in: "set the volume to 30 percent") == .volume(30))
        #expect(SystemCommand.request(in: "Volume 70.") == .volume(70))
        #expect(SystemCommand.request(in: "turn the volume to max") == .volume(100))
        #expect(SystemCommand.request(in: "volume to half") == .volume(50))
    }

    @Test func volumeWithoutALevelOrOutOfRangeIsLeftAlone() {
        #expect(SystemCommand.request(in: "turn the volume up") == nil)
        #expect(SystemCommand.request(in: "set the volume to 400") == nil)
        #expect(SystemCommand.request(in: "what is the volume") == nil)
    }

    @Test func muteAndUnmute() {
        #expect(SystemCommand.request(in: "mute") == .mute(true))
        #expect(SystemCommand.request(in: "Mute the sound.") == .mute(true))
        #expect(SystemCommand.request(in: "unmute the volume") == .mute(false))
        #expect(SystemCommand.request(in: "mute the standup meeting recording") == nil)
    }

    @Test func darkAndLightMode() {
        #expect(SystemCommand.request(in: "switch to dark mode") == .appearance("dark"))
        #expect(SystemCommand.request(in: "Dark mode.") == .appearance("dark"))
        #expect(SystemCommand.request(in: "go to light mode") == .appearance("light"))
        #expect(SystemCommand.request(in: "turn off dark mode") == .appearance("light"))
        #expect(SystemCommand.request(in: "turn light mode off") == .appearance("dark"))
    }

    @Test func lockTheScreen() {
        #expect(SystemCommand.request(in: "lock the screen") == .lock)
        #expect(SystemCommand.request(in: "please lock my mac") == .lock)
        #expect(SystemCommand.request(in: "lock the door of the project") == nil)
    }

    @Test func everythingElseIsLeftToTheRestOfHark() {
        #expect(SystemCommand.request(in: "open slack") == nil)
        #expect(SystemCommand.request(in: "") == nil)
        #expect(SystemCommand.request(in: "open the dark mode settings page and switch to the other thing today please") == nil)
    }
}
