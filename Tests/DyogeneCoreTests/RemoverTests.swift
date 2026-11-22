import Darwin
import Foundation
import Testing
@testable import DyogeneCore

@Suite(.serialized) struct RemoverTests {
    /// Inside the home so the removal policy allows it; removed afterwards.
    let base = NSHomeDirectory() + "/Library/Caches/io.github.0xrd.dyogene.tests/\(UUID().uuidString)"

    init() throws {
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    }

    private func make(_ name: String, bytes: Int = 4096) throws -> String {
        let path = base + "/" + name
        try Data(repeating: 0x41, count: bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test func trashAndPutBack() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }
        let path = try make("trash-me.txt")
        let outcome = try FileRemover.remove(path, mode: .trash)
        #expect(!FileManager.default.fileExists(atPath: path))
        let trashed = try #require(outcome.trashedPath)
        #expect(FileManager.default.fileExists(atPath: trashed))
        try FileRemover.putBack(outcome)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func permanentDelete() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }
        let path = try make("delete-me.txt")
        _ = try FileRemover.remove(path, mode: .permanent)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func secureEraseOverwritesBeforeUnlinking() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }
        let path = try make("secret.bin", bytes: 3_000_000)
        // Keep a descriptor open: after unlink it still shows the data that was on disk.
        let fd = open(path, O_RDONLY)
        defer { close(fd) }
        _ = try FileRemover.remove(path, mode: .secureErase)
        #expect(!FileManager.default.fileExists(atPath: path))
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = pread(fd, &buffer, buffer.count, 0)
        #expect(count == 4096)
        #expect(buffer.filter { $0 == 0x41 }.count < 100)
    }

    @Test func secureEraseFolderAndRefusesHardLinks() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.createDirectory(atPath: base + "/dir/sub", withIntermediateDirectories: true)
        _ = try make("dir/a.bin")
        _ = try make("dir/sub/b.bin")
        _ = try FileRemover.remove(base + "/dir", mode: .secureErase)
        #expect(!FileManager.default.fileExists(atPath: base + "/dir"))

        let original = try make("linked.bin")
        link(original, base + "/linked-2.bin")
        #expect(throws: FileRemover.Failure.self) { try FileRemover.remove(original, mode: .secureErase) }
        #expect(FileManager.default.fileExists(atPath: original))
    }

    @Test func policyIsEnforcedByTheRemoverItself() {
        #expect(throws: FileRemover.Failure.self) { try FileRemover.remove("/System/Library", mode: .trash) }
        #expect(throws: FileRemover.Failure.self) { try FileRemover.remove(NSHomeDirectory(), mode: .permanent) }
        #expect(throws: FileRemover.Failure.self) { try FileRemover.remove(NSHomeDirectory() + "/Documents", mode: .secureErase) }
    }
}

@Suite(.serialized) struct PreflightTests {
    let base = NSHomeDirectory() + "/Library/Caches/io.github.0xrd.dyogene.tests/\(UUID().uuidString)"

    @Test func secureEraseRefusesBeforeTouchingAnything() throws {
        defer { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.createDirectory(atPath: base + "/dir", withIntermediateDirectories: true)
        let first = base + "/dir/a.bin"
        try Data(repeating: 0x41, count: 4096).write(to: URL(fileURLWithPath: first))
        try Data(repeating: 0x42, count: 4096).write(to: URL(fileURLWithPath: base + "/dir/b.bin"))
        link(base + "/dir/b.bin", base + "/b-other-name.bin")
        #expect(FileRemover.preflight(base + "/dir", mode: .secureErase) != nil)
        #expect(throws: FileRemover.Failure.self) { try FileRemover.remove(base + "/dir", mode: .secureErase) }
        // Nothing was overwritten.
        #expect(try Data(contentsOf: URL(fileURLWithPath: first)) == Data(repeating: 0x41, count: 4096))
        #expect(FileRemover.preflight(base + "/dir", mode: .permanent) == nil)
    }
}
