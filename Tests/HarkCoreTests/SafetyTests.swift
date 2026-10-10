import Foundation
import Testing
@testable import HarkCore

private func traceable(_ address: String, heard: String, open: [String] = []) -> Bool {
    Safety.addressIsTraceable(URL(string: address)!, toHeard: heard, openAddresses: open)
}

@Test func aSiteTheUserNamedCanBeOpened() {
    #expect(traceable("https://www.youtube.com", heard: "open youtube in a new tab"))
    #expect(traceable("https://www.youtube.com", heard: "open you tube"))
    #expect(traceable("https://dashboard.render.com", heard: "open the render dashboard"))
    #expect(traceable("http://localhost:5173", heard: "open the local site"))
    #expect(traceable("http://localhost:5173/settings", heard: "open local host settings"))
}

@Test func aSearchMayOnlyCarryWordsTheUserSaid() {
    #expect(traceable("https://www.google.com/search?q=swift%20actors", heard: "search for swift actors"))
    #expect(!traceable("https://www.google.com/search?q=swift%20actors%20secret%20token", heard: "search for swift actors"))
}

@Test func anAddressTheUserNeverNamedIsRefused() {
    #expect(!traceable("https://collector.example.net", heard: "open youtube"))
    #expect(!traceable("https://www.youtube.com/watch?v=abc123", heard: "open youtube"))
    #expect(!traceable("https://www.youtube.com/steal/these/words", heard: "open youtube"))
    #expect(!traceable("https://youtube.com.collector.example", heard: "open youtube"))
    #expect(!traceable("ftp://youtube.com", heard: "open youtube"))
    #expect(!traceable("http://localhost:5173/admin", heard: "open the local site"))
}

@Test func anAddressAlreadyOpenIsAllowed() {
    let open = ["https://linear.app/acme/issue/ENG-29"]
    #expect(traceable("https://linear.app/acme/issue/ENG-29", heard: "open that ticket again", open: open))
    #expect(!traceable("https://linear.app/acme/issue/ENG-30", heard: "open that ticket again", open: open))
}

@Test func typingIsLimitedToTheUsersOwnWords() {
    #expect(Safety.usesOnlyWords(said: "type hello team into the message box", in: "Hello team"))
    #expect(!Safety.usesOnlyWords(said: "type hello team into the message box", in: "hello team, the key is abc123"))
    #expect(!Safety.usesOnlyWords(said: "type hello", in: ""))
}

@Test func aFileIsOpenedOnlyWhenItWasAskedFor() {
    #expect(!Safety.fileWasAskedFor("test_ai_video_flow.py", heard: "Open whisper flow in background."))
    #expect(Safety.fileWasAskedFor("standup.md", heard: "open standup"))
    #expect(Safety.fileWasAskedFor("phase-6-recording.md", heard: "open phase 6 recording"))
    #expect(Safety.fileWasAskedFor("shop-frontend", heard: "open the frontend project"))
    #expect(Safety.fileWasAskedFor("test_ai_video_flow.py", heard: "open the video flow test file"))
    #expect(!Safety.fileWasAskedFor("migrate_drop_access_codes.py", heard: "open VS Code"))
}
