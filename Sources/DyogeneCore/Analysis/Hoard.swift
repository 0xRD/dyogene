import Foundation

/// The heaviest things on the disk, as units you could act on.
public enum Hoard {
    public enum Mode: String, Sendable, CaseIterable {
        /// Files and packages (apps, photo libraries...): what Finder shows as one item.
        case items
        /// Folders whose weight sits in files they hold directly (a folder of videos, a
        /// download folder), as opposed to containers of other folders.
        case folders
    }

    public struct Filter: Sendable {
        public var mode: Mode = .items
        /// Only items unused for at least this long (seconds); 0 for any.
        public var unusedFor: Double = 0
        public var kind: Kind? = nil
        public var minimumSize: UInt64 = 0
        public var limit = 100
        public init(mode: Mode = .items, unusedFor: Double = 0, kind: Kind? = nil, minimumSize: UInt64 = 0, limit: Int = 100) {
            self.mode = mode
            self.unusedFor = unusedFor
            self.kind = kind
            self.minimumSize = minimumSize
            self.limit = limit
        }
    }

    public static func items(in tree: FileTree, under start: Int = FileTree.root, filter: Filter, now: Double) -> [Int] {
        var candidates: [Int] = []
        var stack = [start]
        while let index = stack.popLast() {
            let node = tree[index]
            if node.flags.contains(.removed) || node.size == 0 { continue }
            switch filter.mode {
            case .items:
                if index != start && (!node.isDirectory || node.isPackage) {
                    if node.isActionable && !node.flags.contains(.mountPoint) { candidates.append(index) }
                    continue
                }
            case .folders:
                if node.isPackage { continue }
                if index != start && node.isDirectory && !node.flags.contains(.mountPoint) {
                    let direct = tree.children(of: index).reduce(UInt64(0)) { total, child in
                        let childNode = tree[child]
                        let isFile = !childNode.isDirectory || childNode.isPackage
                        return isFile && !childNode.flags.contains(.removed) ? total + childNode.size : total
                    }
                    if Double(direct) >= 0.5 * Double(node.size) { candidates.append(index) }
                }
            }
            if node.isDirectory { stack.append(contentsOf: tree.children(of: index)) }
        }

        let matching = candidates.filter { index in
            let node = tree[index]
            if node.size < filter.minimumSize { return false }
            if let kind = filter.kind, node.kind != kind { return false }
            if filter.unusedFor > 0 {
                guard node.lastUsed > 0, now - node.lastUsed >= filter.unusedFor else { return false }
            }
            return true
        }
        return Array(matching.sorted { tree[$0].size > tree[$1].size }.prefix(filter.limit))
    }
}
