import Foundation
import Testing
@testable import HarkCore

private func temporaryFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "hark-tests-\(UUID().uuidString)/\(name)")
}

@Test func missingFileGivesDefaults() throws {
    let config = try Config.load(from: temporaryFile("config.json"))
    #expect(config == Config())
    #expect(config.hotkey == "rightOption")
    #expect(config.clipLimit == 5000)
}

@Test func configRoundTrips() throws {
    let url = temporaryFile("config.json")
    let config = Config(
        hotkey: "f13",
        searchFolders: ["/tmp/projects"],
        repos: ["/tmp/projects/api"],
        aliases: ["the backend": "Shop-backend"],
        routines: [Routine(name: "stop port", steps: [Step(shell: "lsof -ti :{arg}", destructive: true)])],
        clipLimit: 100
    )
    try config.save(to: url)
    #expect(try Config.load(from: url) == config)
}

@Test func partialFileKeepsDefaultsForMissingFields() throws {
    let url = temporaryFile("config.json")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"hotkey": "rightCommand", "routines": [{"name": "branches", "steps": [{"shell": "git branch"}]}]}"#.utf8)
        .write(to: url)
    let config = try Config.load(from: url)
    #expect(config.hotkey == "rightCommand")
    #expect(config.clipLimit == 5000)
    #expect(config.routines.first?.steps.first?.destructive == false)
}
