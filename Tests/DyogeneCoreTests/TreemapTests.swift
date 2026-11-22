import CoreGraphics
import Foundation
import Testing
@testable import DyogeneCore

@Suite struct TreemapTests {
    @Test func areasAreProportionalAndFillTheBounds() {
        let values: [Double] = [600, 300, 120, 80, 40, 20, 10, 5]
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let rects = Treemap.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * value / total
            #expect(abs(Double(rect.width * rect.height) - expected) < expected * 0.001 + 0.5)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        let area = rects.reduce(0) { $0 + Double($1.width * $1.height) }
        #expect(abs(area - Double(bounds.width * bounds.height)) < 1)
    }

    @Test func rectanglesDoNotOverlap() {
        let values: [Double] = (1...40).map { Double(41 - $0) * 3 }
        let rects = Treemap.squarify(values, in: CGRect(x: 10, y: 20, width: 640, height: 480))
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func shapesStayReasonable() {
        let rects = Treemap.squarify([1, 1, 1, 1], in: CGRect(x: 0, y: 0, width: 400, height: 400))
        for rect in rects { #expect(abs(rect.width - rect.height) < 1) }
    }

    @Test func zerosGetEmptyRectangles() {
        let rects = Treemap.squarify([10, 0, 0], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rects[0].width == 100 && rects[0].height == 100)
        #expect(rects[1] == .zero && rects[2] == .zero)
        #expect(Treemap.squarify([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }

    @Test func mapLayoutGroupsTinyItemsAndNests() {
        let tree = DemoTree.make(now: 1_800_000_000)
        let tiles = MapLayout.tiles(for: tree, focus: FileTree.root, in: CGRect(x: 0, y: 0, width: 1000, height: 700))
        #expect(tiles.contains { $0.depth == 0 })
        #expect(tiles.contains { $0.depth == 1 })
        var folder = ScannedFolder(name: "root", flags: [.directory])
        folder.files = [ScannedFile(name: "big", size: 1_000_000, lastUsed: 0, kind: .other, flags: [], count: 1)]
            + (0..<20).map { ScannedFile(name: "f\($0)", size: 10, lastUsed: 0, kind: .other, flags: [], count: 1) }
        folder.finish(parentName: nil)
        let small = TreeBuilder.build(root: folder, rootPath: "/x", scannedAt: Date())
        let grouped = MapLayout.tiles(for: small, focus: FileTree.root, in: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(grouped.count == 2)
        #expect(grouped.last?.node == nil && grouped.last?.groupCount == 20 && grouped.last?.groupSize == 200)
        for tile in tiles { #expect(tile.rect.width >= 1 && tile.rect.height >= 1) }
        let hit = MapLayout.hit(CGPoint(x: 500, y: 350), in: tiles)
        #expect(hit != nil)
    }
}
