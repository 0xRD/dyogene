import Foundation
import Testing
@testable import DyogeneCore

@Suite struct AnalysisTests {
    let now = 1_800_000_000.0

    @Test func hoardListsActionableItemsLargestFirst() {
        let tree = DemoTree.make(now: now)
        let items = Hoard.items(in: tree, filter: .init(mode: .items, limit: 20), now: now)
        #expect(items.count == 20)
        #expect(items.map { tree[$0].size } == items.map { tree[$0].size }.sorted(by: >))
        for index in items {
            #expect(!tree[index].isDirectory || tree[index].isPackage)
            #expect(tree[index].isActionable)
        }
        #expect(["Docker.raw", "Photos Library.photoslibrary"].contains(tree[items[0]].name))
    }

    @Test func hoardFiltersByAgeAndKind() {
        let tree = DemoTree.make(now: now)
        let old = Hoard.items(in: tree, filter: .init(mode: .items, unusedFor: 365 * Dust.day), now: now)
        #expect(!old.isEmpty)
        for index in old { #expect(now - tree[index].lastUsed >= 365 * Dust.day) }
        let videos = Hoard.items(in: tree, filter: .init(mode: .items, kind: .video), now: now)
        for index in videos { #expect(tree[index].kind == .video) }
        let folders = Hoard.items(in: tree, filter: .init(mode: .folders), now: now)
        for index in folders { #expect(tree[index].isDirectory && !tree[index].isPackage) }
    }

    @Test func suspectsFindTheUsualPlacesWithoutDoubleCounting() {
        let tree = DemoTree.make(now: now)
        let findings = Suspects.findings(in: tree, home: DemoTree.home, now: now)
        let ids = Set(findings.map(\.id))
        for expected in ["trash", "installers", "user-caches", "xcode-derived-data", "node-modules", "swift-build",
                         "old-downloads", "simulators", "docker", "ios-backups", "xcode-archives", "xcode-device-support"] {
            #expect(ids.contains(expected), "missing \(expected)")
        }
        var seen = Set<Int>()
        for finding in findings {
            for node in finding.nodes {
                #expect(seen.insert(node).inserted)
                #expect(!tree.lineage(of: node).dropLast().contains(where: seen.contains))
            }
        }
        // Installers in Downloads are not counted again as old downloads.
        let installers = findings.first { $0.id == "installers" }!.nodes
        let old = findings.first { $0.id == "old-downloads" }!.nodes
        #expect(Set(installers).isDisjoint(with: old))
    }

    @Test func reportIsValidJSON() throws {
        let tree = DemoTree.make(now: now)
        let full = Report.full(tree: tree, volume: DemoTree.volume(for: tree), fullDiskAccess: true, home: DemoTree.home, now: now)
        let data = Data(Report.json(full).utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["suspects"] != nil)
        let summary = full.summary
        let byKindTotal = summary.byKind.reduce(0) { $0 + $1.size }
        let byAgeTotal = summary.byAge.reduce(0) { $0 + $1.size }
        #expect(byKindTotal == tree.totalSize)
        #expect(byAgeTotal == tree.totalSize)
    }

    @Test func pathsRoundTrip() {
        let tree = DemoTree.make(now: now)
        for index in stride(from: 0, to: tree.nodes.count, by: 37) where tree[index].isActionable {
            #expect(tree.index(ofPath: tree.path(of: index)) == index)
        }
    }
}
