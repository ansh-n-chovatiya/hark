import Foundation
import Testing
@testable import HarkCore

@Test func aSavedLinkIsFoundByItsName() {
    let links = ["backend logs": "https://dashboard.example.com/logs/shop-backend", "board": "https://tracker.example.com/board"]
    #expect(Links.find("the Backend Logs", in: links)?.address.absoluteString == "https://dashboard.example.com/logs/shop-backend")
    #expect(Links.find("board page", in: links)?.name == "board")
    #expect(Links.find("logs", in: links) == nil)
    #expect(Links.find("", in: links) == nil)
}

@Test func aSavedLinkMustBeAWebAddress() {
    #expect(Links.find("notes", in: ["notes": "file:///etc/hosts"]) == nil)
}

@Test func askingToBeToldIsSplitFromTheCommand() {
    #expect(Background.split("run tests and tell me when it finishes").command == "run tests")
    #expect(Background.split("run tests and tell me when it finishes").inBackground)
    #expect(Background.split("pull all in the background").command == "pull all")
    #expect(Background.split("Let me know when the build is done").command == "")
    #expect(!Background.split("open the projects folder").inBackground)
    #expect(Background.split("open the projects folder").command == "open the projects folder")
}

@Test func wrongCommandsAreKept() {
    let url = FileManager.default.temporaryDirectory.appending(path: "hark-tests-\(UUID().uuidString)/wrong.jsonl")
    let log = WrongLog(url: url)
    let entry = WrongLog.Entry(at: Date(timeIntervalSince1970: 1_800_000_000), heard: "open the board", did: "Opened Notes", wanted: "the task board")
    log.append(entry)
    log.append(entry)
    #expect(log.all() == [entry, entry])
}

@Test func backgroundIsRecognisedHoweverItIsLedInto() {
    let heard = Background.split("Open whisper flow button background. Don't open window for it")
    #expect(heard.command == "open whisper flow")
    #expect(heard.inBackground)
    #expect(Background.split("open slack and keep it in the background").command == "open slack")
}
