import Foundation
import Testing

@testable import HarkCore

@Suite struct DictationTests {
    @Test func dropsFillerWordsButKeepsWordsThatContainThem() {
        #expect(Dictation.tidy("um so uh this is, er, fine") == "So this is, fine")
        #expect(Dictation.tidy("the umbrella is humming") == "The umbrella is humming")
    }

    @Test func removesLineBreaksAndExtraSpaces() {
        #expect(Dictation.tidy("first line\nsecond   line\r\n third") == "First line second line third")
    }

    @Test func capitalisesOnlyTheFirstLetterAndLeavesTheRestAlone() {
        #expect(Dictation.tidy("check the iPhone and NASA notes") == "Check the iPhone and NASA notes")
    }

    @Test func nothingSaidTypesNothing() {
        #expect(Dictation.tidy("   ") == "")
        #expect(Dictation.tidy("um uh") == "")
    }

    @Test func neverAddsWords() {
        let said = "write a note about the budget"
        let tidy = Dictation.tidy(said)
        #expect(tidy.lowercased() == said)
    }

    @Test func theDictationKeyIsOffByDefaultAndSurvivesSaving() throws {
        #expect(Config().dictationKey == "")
        var config = Config()
        config.dictationKey = "leftControl"
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data).dictationKey == "leftControl")
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).dictationKey == "")
    }
}
