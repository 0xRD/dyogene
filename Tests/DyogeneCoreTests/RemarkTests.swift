import Testing
@testable import DyogeneCore

@Suite struct RemarkTests {
    let now = 1_800_000_000.0

    @Test func picksTheRightRemark() throws {
        let tree = DemoTree.make(now: now)
        func remark(_ path: String) throws -> Remark {
            Remark.about(try #require(tree.index(ofPath: DemoTree.home + "/" + path)), in: tree, now: now)
        }
        #expect(try remark("Movies/Wedding film master.mp4").mood == .curious)
        #expect(try remark("Movies/Wedding film master.mp4").text.contains("Treasure"))
        #expect(try remark("Downloads/Design tool installer.dmg").text.contains("installer"))
        #expect(try remark("Library/Caches").text.contains("faster"))
        #expect(try remark("Projects/website/node_modules").text.contains("leftovers"))
        #expect(try remark("Pictures/Photos Library.photoslibrary").mood == .pleased)
        #expect(Remark.about(FileTree.root, in: tree, now: now).text.contains("jar"))
    }

    @Test func neverMentionsContents() {
        let tree = DemoTree.make(now: now)
        for index in tree.nodes.indices {
            let text = Remark.about(index, in: tree, now: now).text
            #expect(!text.isEmpty)
            #expect(!text.contains("—"))
        }
    }
}
