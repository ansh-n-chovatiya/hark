import Foundation
import Testing

@testable import HarkCore

@Suite struct ModelProvidersTests {
    @Test func findsAProviderByItsAddressIgnoringATrailingSlash() {
        #expect(ModelProvider.matching(address: "https://api.openai.com/v1/") == .openAI)
        #expect(ModelProvider.matching(address: " http://127.0.0.1:11434/v1 ") == .ollama)
        #expect(ModelProvider.matching(address: "https://models.example.com/v1") == nil)
    }

    @Test func readsAnOpenAIStyleListAndDropsModelsThatCannotChat() {
        let json = #"{"data":[{"id":"gpt-4o-mini"},{"id":"text-embedding-3-small"},{"id":"whisper-1"},{"id":"gpt-4o"}]}"#
        #expect(ModelList.parse(Data(json.utf8)) == ["gpt-4o", "gpt-4o-mini"])
    }

    @Test func readsGeminisListAndRemovesThePrefix() {
        let json = #"{"data":[{"id":"models/gemini-2.0-flash"},{"id":"models/text-embedding-004"},{"id":"models/gemini-2.0-flash"}]}"#
        #expect(ModelList.parse(Data(json.utf8)) == ["gemini-2.0-flash"])
        let native = #"{"models":[{"name":"models/gemini-pro"}]}"#
        #expect(ModelList.parse(Data(native.utf8)) == ["gemini-pro"])
    }

    @Test func streamingOnlyAndSpecialistModelsAreNotOffered() {
        let json = #"{"data":[{"id":"models/gemini-3.8-live-extended-thinking"},{"id":"models/gemini-robotics-er"},{"id":"models/gemini-3.8-flash"}]}"#
        #expect(ModelList.parse(Data(json.utf8)) == ["gemini-3.8-flash"])
    }

    @Test func anUnreadableAnswerGivesAnEmptyList() {
        #expect(ModelList.parse(Data("not json".utf8)).isEmpty)
        #expect(ModelList.parse(Data("{}".utf8)).isEmpty)
    }
}
