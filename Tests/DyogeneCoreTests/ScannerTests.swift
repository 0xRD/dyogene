import Darwin
import Foundation
import Testing
@testable import DyogeneCore

@Suite struct ScannerTests {
    /// A scratch folder with known content, removed afterwards.
    final class Fixture {
        let root: String
        init() throws {
            root = NSTemporaryDirectory() + "dyogene-scan-\(UUID().uuidString)"
            let fm = FileManager.default
            try fm.createDirectory(atPath: root + "/movies/old", withIntermediateDirectories: true)
            try fm.createDirectory(atPath: root + "/code/node_modules/pkg", withIntermediateDirectories: true)
            try fm.createDirectory(atPath: root + "/App.app/Contents", withIntermediateDirectories: true)
            try Data(count: 3_000_000).write(to: URL(fileURLWithPath: root + "/movies/film.mov"))
            try Data(count: 1_000_000).write(to: URL(fileURLWithPath: root + "/movies/old/clip.mov"))
            try Data(count: 200_000).write(to: URL(fileURLWithPath: root + "/App.app/Contents/binary"))
            for i in 0..<40 {
                try Data(count: 5_000).write(to: URL(fileURLWithPath: root + "/code/node_modules/pkg/f\(i).js"))
            }
            // A hard link must be counted once, a symlink must not be followed.
            link(root + "/movies/film.mov", root + "/movies/film-link.mov")
            symlink(root + "/movies", root + "/shortcut")
        }
        deinit { try? FileManager.default.removeItem(atPath: root) }

        /// What the disk says, like `du`: allocated blocks, hard links once.
        func allocated() -> UInt64 {
            var total: UInt64 = 0
            var seen = Set<UInt64>()
            let enumerator = FileManager.default.enumerator(atPath: root)!
            while let relative = enumerator.nextObject() as? String {
                var info = stat()
                guard lstat(root + "/" + relative, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR else { continue }
                if info.st_nlink > 1 && !seen.insert(UInt64(info.st_ino)).inserted { continue }
                total += UInt64(info.st_blocks) * 512
            }
            return total
        }
    }

    @Test func sizesMatchTheDiskAndHardLinksCountOnce() async throws {
        let fixture = try Fixture()
        let tree = try await Scanner(options: ScanOptions(root: fixture.root, protectedSkips: [])).scan()
        #expect(tree.totalSize == fixture.allocated())
        let movies = try #require(tree.index(ofPath: fixture.root + "/movies"))
        let linked = tree.children(of: movies).filter { tree[$0].flags.contains(.hardLink) }
        #expect(linked.count == 1)
        let shortcut = try #require(tree.index(ofPath: fixture.root + "/shortcut"))
        #expect(tree[shortcut].flags.contains(.symlink))
        #expect(!tree[shortcut].isDirectory)
    }

    @Test func childrenAreSortedAndKindsGuessed() async throws {
        let fixture = try Fixture()
        let tree = try await Scanner(options: ScanOptions(root: fixture.root, protectedSkips: [])).scan()
        for index in tree.nodes.indices {
            let sizes = tree.children(of: index).map { tree[$0].size }
            #expect(sizes == sizes.sorted(by: >))
        }
        let movies = try #require(tree.index(ofPath: fixture.root + "/movies"))
        #expect(tree[movies].kind == .video)
        let app = try #require(tree.index(ofPath: fixture.root + "/App.app"))
        #expect(tree[app].isPackage && tree[app].kind == .app)
        let modules = try #require(tree.index(ofPath: fixture.root + "/code/node_modules"))
        #expect(tree[modules].kind == .developer)
    }

    @Test func smallFilesAreGrouped() async throws {
        let fixture = try Fixture()
        let tree = try await Scanner(options: ScanOptions(root: fixture.root, protectedSkips: [])).scan()
        let pkg = try #require(tree.index(ofPath: fixture.root + "/code/node_modules/pkg"))
        let children = tree.children(of: pkg).map { tree[$0] }
        #expect(children.count == 17) // 16 largest kept + 1 group
        let group = try #require(children.first { $0.flags.contains(.smallGroup) })
        #expect(group.itemCount == 24)
        #expect(tree[pkg].itemCount == 40)
        #expect(tree.path(of: tree.children(of: pkg).first { tree[$0].flags.contains(.smallGroup) }!) == fixture.root + "/code/node_modules/pkg")
    }

    @Test func protectedAndExcludedFoldersAreSkipped() async throws {
        let fixture = try Fixture()
        let options = ScanOptions(root: fixture.root, exclusions: [fixture.root + "/code"], protectedSkips: [fixture.root + "/movies"])
        let tree = try await Scanner(options: options).scan()
        #expect(tree.index(ofPath: fixture.root + "/code") == nil)
        let movies = try #require(tree.index(ofPath: fixture.root + "/movies"))
        #expect(tree[movies].flags.contains(.needsAccess))
        #expect(tree[movies].size == 0)
    }

    @Test func removalUpdatesAncestors() async throws {
        let fixture = try Fixture()
        var tree = try await Scanner(options: ScanOptions(root: fixture.root, protectedSkips: [])).scan()
        let clip = try #require(tree.index(ofPath: fixture.root + "/movies/old/clip.mov"))
        let before = tree.totalSize
        let size = tree[clip].size
        tree.markRemoved(clip)
        #expect(tree.totalSize == before - size)
        #expect(tree.visibleChildren(of: tree.parent(of: clip)!).isEmpty)
    }

    @Test func missingRootFails() async {
        await #expect(throws: Scanner.Failure.self) {
            try await Scanner(options: ScanOptions(root: "/nonexistent-\(UUID().uuidString)", protectedSkips: [])).scan()
        }
    }
}
