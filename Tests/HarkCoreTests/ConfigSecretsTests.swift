import Foundation
import Testing

@testable import HarkCore

private final class FakeStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private let fails: Bool
    private let forgets: Bool
    var deleted = false

    init(holding value: String? = nil, fails: Bool = false, forgets: Bool = false) {
        self.value = value
        self.fails = fails
        self.forgets = forgets
    }

    var held: String? { lock.withLock { value } }
    func read() -> String? { lock.withLock { value } }
    func write(_ secret: String) throws {
        if fails { throw NSError(domain: "keychain", code: -25293) }
        if !forgets { lock.withLock { value = secret } }
    }
    func delete() { lock.withLock { value = nil; deleted = true } }
}

@Suite struct ConfigSecretsTests {
    @Test func aKeyFoundInTheFileIsMovedOutOfIt() {
        let store = FakeStore()
        let file = Config(modelKey: "secret-key")
        let result = ConfigSecrets.resolve(loaded: file, store: store)
        #expect(store.held == "secret-key")
        #expect(result.inMemory.modelKey == "secret-key")
        #expect(result.rewrite?.modelKey == "")
    }

    @Test func aBlankFileTakesTheKeyFromTheStore() {
        let store = FakeStore(holding: "from-keychain")
        let result = ConfigSecrets.resolve(loaded: Config(), store: store)
        #expect(result.inMemory.modelKey == "from-keychain")
        #expect(result.rewrite == nil)
    }

    @Test func aKeyTypedIntoTheFileLaterWinsOverTheOldOne() {
        let store = FakeStore(holding: "old")
        let result = ConfigSecrets.resolve(loaded: Config(modelKey: "new"), store: store)
        #expect(store.held == "new")
        #expect(result.inMemory.modelKey == "new")
    }

    @Test func aStoreThatRefusesNeverLosesTheKey() {
        let store = FakeStore(fails: true)
        let result = ConfigSecrets.resolve(loaded: Config(modelKey: "secret-key"), store: store)
        #expect(result.inMemory.modelKey == "secret-key")
        #expect(result.rewrite == nil)
        let onDisk = ConfigSecrets.forDisk(Config(modelKey: "secret-key"), store: store)
        #expect(onDisk.modelKey == "secret-key")
    }

    @Test func savingKeepsTheKeyInTheStoreAndOutOfTheFile() throws {
        let store = FakeStore()
        var config = Config(modelKey: "secret-key")
        config.model = "gemini-flash"
        let onDisk = ConfigSecrets.forDisk(config, store: store)
        #expect(store.held == "secret-key")
        #expect(onDisk.modelKey == "")
        #expect(onDisk.model == "gemini-flash")
        let text = String(decoding: try JSONEncoder().encode(onDisk), as: UTF8.self)
        #expect(!text.contains("secret-key"))
    }

    @Test func clearingTheKeyRemovesItFromTheStore() {
        let store = FakeStore(holding: "secret-key")
        _ = ConfigSecrets.forDisk(Config(), store: store, clearing: true)
        #expect(store.deleted)
        #expect(store.held == nil)
    }

    @Test func anEmptyKeyThatWasJustNotReadNeverRemovesTheStoredOne() {
        let store = FakeStore(holding: "secret-key")
        // A locked Keychain or an unreadable settings file gives an empty key; saving then must not delete it.
        _ = ConfigSecrets.forDisk(Config(), store: store)
        #expect(!store.deleted)
        #expect(store.held == "secret-key")
    }

    @Test func aStoreThatSaysYesButKeepsNothingNeverLosesTheKey() {
        let store = FakeStore(forgets: true)
        let result = ConfigSecrets.resolve(loaded: Config(modelKey: "secret-key"), store: store)
        #expect(result.rewrite == nil)
        #expect(ConfigSecrets.forDisk(Config(modelKey: "secret-key"), store: store).modelKey == "secret-key")
    }
}
