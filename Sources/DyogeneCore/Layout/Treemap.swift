import CoreGraphics

/// Squarified treemap (Bruls, Huizing, van Wijk, 2000): rectangles whose areas are proportional
/// to the values and whose shapes stay close to squares, so they are easy to compare and label.
public enum Treemap {
    /// `values` must be sorted largest first. Returns one rectangle per value, in the same order;
    /// zero or negative values get an empty rectangle.
    public static func squarify(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        let areas = values.map { max(0, $0) * scale }
        let count = areas.lastIndex(where: { $0 > 0 }).map { $0 + 1 } ?? 0

        var free = bounds
        var start = 0
        while start < count {
            let side = Double(min(free.width, free.height))
            var end = start + 1
            var sum = areas[start]
            var worst = worstRatio(sum: sum, smallest: areas[start], largest: areas[start], side: side)
            while end < count {
                let candidateSum = sum + areas[end]
                let candidate = worstRatio(sum: candidateSum, smallest: areas[end], largest: areas[start], side: side)
                if candidate > worst { break }
                sum = candidateSum
                worst = candidate
                end += 1
            }
            free = place(areas[start..<end], sum: sum, isLast: end == count, in: free, into: &result, offset: start)
            start = end
        }
        return result
    }

    private static func worstRatio(sum: Double, smallest: Double, largest: Double, side: Double) -> Double {
        guard sum > 0, smallest > 0, side > 0 else { return .infinity }
        let side2 = side * side
        let sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }

    /// Lays a row along the short side of `free` and returns what is left.
    private static func place(_ row: ArraySlice<Double>, sum: Double, isLast: Bool, in free: CGRect,
                              into result: inout [CGRect], offset: Int) -> CGRect {
        if free.width >= free.height {
            // A column on the left.
            let width = isLast ? free.width : CGFloat(sum / Double(free.height))
            var y = free.minY
            for (i, area) in row.enumerated() {
                let last = i == row.count - 1
                let height = last ? free.maxY - y : CGFloat(area / Double(width))
                result[offset + i] = CGRect(x: free.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: free.minX + width, y: free.minY, width: max(0, free.width - width), height: free.height)
        } else {
            // A row on top.
            let height = isLast ? free.height : CGFloat(sum / Double(free.width))
            var x = free.minX
            for (i, area) in row.enumerated() {
                let last = i == row.count - 1
                let width = last ? free.maxX - x : CGFloat(area / Double(height))
                result[offset + i] = CGRect(x: x, y: free.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(0, free.height - height))
        }
    }
}

/// One drawn rectangle of the map.
public struct MapTile: Sendable, Hashable {
    /// Node index in the tree, or nil for an "N smaller items" tile.
    public let node: Int?
    public let rect: CGRect
    /// 0 for children of the focused folder, 1 for their children, and so on.
    public let depth: Int
    /// The rectangle of the tile's own content, below its header (equal to `rect` for leaves).
    public let contentRect: CGRect
    /// True when the tile has nested tiles drawn inside it.
    public let hasChildren: Bool
    /// For an "N smaller items" tile: how many items and how much space.
    public let groupCount: Int
    public let groupSize: UInt64
    /// The folder the tile belongs to (for grouped tiles and hit testing).
    public let parent: Int
}

/// Turns a tree into nested tiles: the children of the focused folder, and inside the large ones
/// their own children, as deep as space allows.
public enum MapLayout {
    public struct Options: Sendable {
        public var maxDepth = 3
        /// Below this area (points²) an item joins the "N smaller items" tile of its folder.
        public var minTileArea: CGFloat = 140
        /// A tile gets nested children only when it is at least this big.
        public var minNestWidth: CGFloat = 96
        public var minNestHeight: CGFloat = 64
        public var headerHeight: CGFloat = 20
        public var gap: CGFloat = 2
        public init() {}
    }

    public static func tiles(for tree: FileTree, focus: Int, in bounds: CGRect, options: Options = Options()) -> [MapTile] {
        var tiles: [MapTile] = []
        tiles.reserveCapacity(512)
        layout(tree: tree, folder: focus, in: bounds, depth: 0, options: options, into: &tiles)
        return tiles
    }

    private static func layout(tree: FileTree, folder: Int, in bounds: CGRect, depth: Int,
                               options: Options, into tiles: inout [MapTile]) {
        let children = tree.visibleChildren(of: folder)
        let total = children.reduce(UInt64(0)) { $0 + tree[$1].size }
        guard total > 0, bounds.width > 1, bounds.height > 1 else { return }

        // Items too small to see become one grouped tile at the end.
        let areaPerByte = Double(bounds.width * bounds.height) / Double(total)
        var kept: [Int] = []
        var groupSize: UInt64 = 0
        var groupCount = 0
        for child in children {
            let area = Double(tree[child].size) * areaPerByte
            if area >= Double(options.minTileArea) || (kept.isEmpty && groupCount == 0) {
                kept.append(child)
            } else {
                groupSize += tree[child].size
                groupCount += 1
            }
        }
        if groupCount == 1, let last = children.last {
            // A group of one is just that item.
            kept.append(last)
            groupSize = 0
            groupCount = 0
        }

        var values = kept.map { Double(tree[$0].size) }
        if groupCount > 0 {
            // Always visible, even when its true share is a fraction of a point; its label tells the real size.
            // Squarify can make it a thin strip, so reserve a little more than the minimum tile.
            let reserved = max(3 * Double(options.minTileArea), 0.015 * Double(bounds.width * bounds.height))
            values.append(max(Double(groupSize), reserved / areaPerByte))
        }
        let rects = Treemap.squarify(values, in: bounds)

        for (i, rect) in rects.enumerated() {
            let inset = rect.insetBy(dx: options.gap / 2, dy: options.gap / 2)
            guard inset.width >= 1, inset.height >= 1 else { continue }
            if i >= kept.count {
                tiles.append(MapTile(node: nil, rect: inset, depth: depth, contentRect: inset, hasChildren: false,
                                     groupCount: groupCount, groupSize: groupSize, parent: folder))
                continue
            }
            let child = kept[i]
            let node = tree[child]
            let canNest = node.isDirectory && !node.isPackage && depth + 1 < options.maxDepth
                && inset.width >= options.minNestWidth && inset.height >= options.minNestHeight
                && node.childCount > 0
            if canNest {
                let content = CGRect(x: inset.minX + 2, y: inset.minY + options.headerHeight,
                                     width: inset.width - 4, height: inset.height - options.headerHeight - 2)
                tiles.append(MapTile(node: child, rect: inset, depth: depth, contentRect: content, hasChildren: true,
                                     groupCount: 0, groupSize: 0, parent: folder))
                layout(tree: tree, folder: child, in: content, depth: depth + 1, options: options, into: &tiles)
            } else {
                tiles.append(MapTile(node: child, rect: inset, depth: depth, contentRect: inset, hasChildren: false,
                                     groupCount: 0, groupSize: 0, parent: folder))
            }
        }
    }

    /// The deepest tile under a point.
    public static func hit(_ point: CGPoint, in tiles: [MapTile]) -> MapTile? {
        // Children are appended after their parent, so the last match is the deepest.
        tiles.last { $0.rect.contains(point) }
    }

    /// The top-level tile (depth 0) that contains a tile, used to zoom one level at a time.
    public static func topLevel(containing point: CGPoint, in tiles: [MapTile]) -> MapTile? {
        tiles.first { $0.depth == 0 && $0.rect.contains(point) }
    }
}
