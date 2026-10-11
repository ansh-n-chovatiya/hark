import Foundation
import Testing

import HarkCore
@testable import HarkMac

/// A folder in the home folder (outside the temporary areas the sandbox leaves open), removed afterwards.
private func probeFolder() throws -> URL {
    let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".hark-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func run(_ command: String, allowingChanges: Bool) async throws -> ToolResult {
    try await RunCommandTool(allowingChanges: allowingChanges).call(.object(["command": .string(command)]))
}

@Suite struct RunCommandToolTests {
    @Test func itAlwaysAsksFirst() {
        #expect(RunCommandTool(allowingChanges: false).spec.kind == .destructive)
        #expect(RunCommandTool(allowingChanges: true).spec.kind == .destructive)
        #expect(RunCommandTool(allowingChanges: false).describe(.object(["command": .string("ls")])) == "Run in the terminal: ls")
    }

    @Test func itShowsTheUserWhatWasPrintedButNotTheModel() async throws {
        let result = try await run("echo hello from the terminal", allowingChanges: false)
        #expect(result.summary == "hello from the terminal")
        #expect(!result.output.contains("hello"))
    }

    @Test func readOnlyCannotWriteDeleteOrMove() async throws {
        let folder = try probeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = folder.appending(path: "keep.txt")
        try "keep".write(to: existing, atomically: true, encoding: .utf8)

        _ = try await run("echo x > '\(folder.path)/new.txt'", allowingChanges: false)
        _ = try await run("rm '\(existing.path)'", allowingChanges: false)
        _ = try await run("mv '\(existing.path)' '\(folder.path)/moved.txt'", allowingChanges: false)
        _ = try await run("echo more >> '\(existing.path)'", allowingChanges: false)

        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "new.txt").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "moved.txt").path))
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
    }

    @Test func allowingChangesStillCannotDeleteOrMove() async throws {
        let folder = try probeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = folder.appending(path: "keep.txt")
        try "keep".write(to: existing, atomically: true, encoding: .utf8)

        _ = try await run("echo made > '\(folder.path)/new.txt'", allowingChanges: true)
        _ = try await run("rm '\(existing.path)'", allowingChanges: true)
        _ = try await run("mv '\(existing.path)' '\(folder.path)/moved.txt'", allowingChanges: true)

        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "new.txt").path))
        #expect(FileManager.default.fileExists(atPath: existing.path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "moved.txt").path))
    }

    @Test func aFailedCommandIsReportedAndATooLongOneRefused() async throws {
        let failed = try await run("exit 3", allowingChanges: false)
        #expect(failed.summary?.contains("failed") == true)
        await #expect(throws: ItemToolError.self) { _ = try await run(String(repeating: "a", count: 700), allowingChanges: false) }
        await #expect(throws: ItemToolError.self) { _ = try await run("   ", allowingChanges: false) }
    }
}
