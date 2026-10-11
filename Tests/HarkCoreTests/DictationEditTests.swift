import Foundation
import Testing

@testable import HarkCore

@Suite struct DictationEditTests {
    @Test func editsAreRecognisedOnlyWhenSaidAlone() {
        #expect(DictationCommand.parse("Scratch that.") == .scratch)
        #expect(DictationCommand.parse("change their to there") == .replace(old: "their", new: "there"))
        #expect(DictationCommand.parse("replace foo with bar") == .replace(old: "foo", new: "bar"))
        #expect(DictationCommand.parse("correct that to Priya") == .replace(old: "", new: "priya"))
        #expect(DictationCommand.parse("select last word") == .select(.lastWord))
        #expect(DictationCommand.parse("go to the end") == .select(.end))
        #expect(DictationCommand.parse("delete selection") == .deleteSelection)
        #expect(DictationCommand.parse("learn the word Kubernetes") == .learn("kubernetes"))
        #expect(DictationCommand.parse("I will scratch that off the list later today") == nil)
        #expect(DictationCommand.parse("change the world") == nil)
    }

    @Test func aTypedSpanIsFoundOnlyRightBeforeTheCursor() {
        let value = "Dear team. Hello world"
        let found = TypedSpan.range(of: "Hello world", in: value, caret: 22)
        #expect(found == NSRange(location: 11, length: 11))
        #expect(TypedSpan.range(of: "Hello world", in: value, caret: 15) == nil)
        #expect(TypedSpan.range(of: "Hello there", in: value, caret: 22) == nil)
        #expect(TypedSpan.range(of: "", in: value, caret: 22) == nil)
    }

    @Test func theLastMatchInsideTheSpanIsTheTarget() {
        let value = "Notes. their cat and their dog"
        let span = NSRange(location: 7, length: 23)
        #expect(TypedSpan.target("their", inSpan: span, of: value) == NSRange(location: 21, length: 5))
        #expect(TypedSpan.target("", inSpan: span, of: value) == NSRange(location: 27, length: 3))
        #expect(TypedSpan.target("missing", inSpan: span, of: value) == nil)
    }

    @Test func spokenPunctuationBecomesCharacters() {
        #expect(Dictation.tidy("hello comma world full stop", spokenPunctuation: true) == "Hello, world.")
        #expect(Dictation.tidy("is it ready question mark yes it is", spokenPunctuation: true) == "Is it ready? Yes it is")
        #expect(Dictation.tidy("ask capital anna about the all caps api", spokenPunctuation: true) == "Ask Anna about the API")
        #expect(Dictation.tidy("literal comma is a word", spokenPunctuation: true) == "Comma is a word")
        #expect(Dictation.tidy("hello comma world", spokenPunctuation: false) == "Hello comma world")
        #expect(Dictation.tidy("say open quote hi close quote now", spokenPunctuation: true) == "Say \u{201C}hi\u{201D} now")
    }
}
