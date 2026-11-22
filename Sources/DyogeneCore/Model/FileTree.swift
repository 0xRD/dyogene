import Foundation

/// What a node is, beyond its size.
public struct NodeFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let directory = NodeFlags(rawValue: 1 << 0)
    /// A bundle Finder shows as one item (.app, .photoslibrary...). Still a directory.
    public static let package = NodeFlags(rawValue: 1 << 1)
    /// Dyogène could not list it (permissions, Full Disk Access).
    public static let unreadable = NodeFlags(rawValue: 1 << 2)
    /// An iCloud placeholder: the content is in the cloud, nothing is stored locally.
    public static let inCloud = NodeFlags(rawValue: 1 << 3)
    /// Many small files of one folder grouped into one node to keep memory low.
    public static let smallGroup = NodeFlags(rawValue: 1 << 4)
    public static let symlink = NodeFlags(rawValue: 1 << 5)
    /// Another volume is mounted here; it is not counted.
    public static let mountPoint = NodeFlags(rawValue: 1 << 6)
    /// A second name of a file already counted (hard link): counted once, here as 0.
    public static let hardLink = NodeFlags(rawValue: 1 << 7)
    /// Moved to the Trash or deleted from Dyogène since the scan.
    public static let removed = NodeFlags(rawValue: 1 << 8)
    /// Skipped because macOS protects it: visible only with Full Disk Access.
    public static let needsAccess = NodeFlags(rawValue: 1 << 9)
}

/// One file, folder or group of small files. Stored in a flat array (`FileTree.nodes`).
public struct Node: Sendable, Codable, Hashable {
    public var name: String
    /// Bytes allocated on disk; for folders, the sum of their content.
    public var size: UInt64
    /// Newest of access and modification dates in the subtree, seconds since 1970; 0 if unknown.
    /// A folder is only as old as its most recently used content.
    public var lastUsed: Double
    /// Files in the subtree (1 for a file, n for a group of small files).
    public var itemCount: UInt64
    public var parent: Int32
    public var firstChild: Int32
    public var childCount: Int32
    public var kind: Kind
    public var flags: NodeFlags

    public init(name: String, size: UInt64, lastUsed: Double, itemCount: UInt64, parent: Int32,
                firstChild: Int32 = 0, childCount: Int32 = 0, kind: Kind, flags: NodeFlags) {
        self.name = name
        self.size = size
        self.lastUsed = lastUsed
        self.itemCount = itemCount
        self.parent = parent
        self.firstChild = firstChild
        self.childCount = childCount
        self.kind = kind
        self.flags = flags
    }

    public var isDirectory: Bool { flags.contains(.directory) }
    public var isPackage: Bool { flags.contains(.package) }
    /// A real item on disk that can be revealed or acted on (not a group of small files).
    public var isActionable: Bool { !flags.contains(.smallGroup) && !flags.contains(.removed) }
}

/// The result of a scan: every node in one array, children of a folder contiguous and sorted by
/// size, largest first. Index 0 is the scanned folder.
public struct FileTree: Sendable, Codable {
    public let rootPath: String
    public let scannedAt: Date
    public private(set) var nodes: [Node]
    /// Folders that could not be listed, kept so the UI can say how much was not seen.
    public let unreadableCount: Int

    public init(rootPath: String, scannedAt: Date, nodes: [Node], unreadableCount: Int) {
        self.rootPath = rootPath
        self.scannedAt = scannedAt
        self.nodes = nodes
        self.unreadableCount = unreadableCount
    }

    public static let root = 0

    /// Where macOS mounts the volume holding apps, users and Library. Its files are the same as
    /// at their usual paths (/Users/... is /System/Volumes/Data/Users/...).
    public static let dataVolume = "/System/Volumes/Data"

    /// The usual spelling of a path: without the data volume prefix.
    public static func displayPath(_ path: String) -> String {
        path.hasPrefix(dataVolume + "/") ? String(path.dropFirst(dataVolume.count)) : path
    }

    /// The path as a person would write it (for the UI and reports).
    public func displayPath(of index: Int) -> String {
        FileTree.displayPath(path(of: index))
    }

    public subscript(index: Int) -> Node { nodes[index] }

    public var totalSize: UInt64 { nodes.first?.size ?? 0 }

    public func children(of index: Int) -> Range<Int> {
        let node = nodes[index]
        let start = Int(node.firstChild)
        return start..<(start + Int(node.childCount))
    }

    /// Children still present, largest first.
    public func visibleChildren(of index: Int) -> [Int] {
        children(of: index).filter { !nodes[$0].flags.contains(.removed) && nodes[$0].size > 0 }
            .sorted { nodes[$0].size > nodes[$1].size }
    }

    public func parent(of index: Int) -> Int? {
        let parent = nodes[index].parent
        return parent < 0 ? nil : Int(parent)
    }

    /// Root first, `index` last.
    public func lineage(of index: Int) -> [Int] {
        var chain = [index]
        var current = index
        while let parent = parent(of: current) {
            chain.append(parent)
            current = parent
        }
        return chain.reversed()
    }

    public func isAncestor(_ ancestor: Int, of index: Int) -> Bool {
        var current = index
        while let parent = parent(of: current) {
            if parent == ancestor { return true }
            current = parent
        }
        return false
    }

    /// Absolute path. For a group of small files, the path of its folder.
    public func path(of index: Int) -> String {
        if index == FileTree.root { return rootPath }
        if nodes[index].flags.contains(.smallGroup), let parent = parent(of: index) {
            return path(of: parent)
        }
        let names = lineage(of: index).dropFirst().map { nodes[$0].name }
        let base = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        return base + "/" + names.joined(separator: "/")
    }

    /// Path relative to the scanned folder, without a leading slash ("" for the root).
    public func relativePath(of index: Int) -> String {
        lineage(of: index).dropFirst().map { nodes[$0].name }.joined(separator: "/")
    }

    /// Finds a node by absolute path, or nil when it is outside the tree or was not kept.
    public func index(ofPath path: String) -> Int? {
        let base = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        var standardized = (path as NSString).standardizingPath
        // Accept /Users/... for a tree of the data volume.
        if base.hasPrefix(FileTree.dataVolume), !standardized.hasPrefix(FileTree.dataVolume + "/"), standardized != FileTree.dataVolume {
            standardized = FileTree.dataVolume + standardized
        }
        if standardized == base || standardized == rootPath { return FileTree.root }
        guard standardized.hasPrefix(base + "/") else { return nil }
        var current = FileTree.root
        for component in standardized.dropFirst(base.count + 1).split(separator: "/") {
            guard let next = children(of: current).first(where: {
                nodes[$0].name == component && !nodes[$0].flags.contains(.smallGroup)
            }) else { return nil }
            current = next
        }
        return current
    }

    /// Marks a node as gone and takes its size and item count out of its ancestors.
    public mutating func markRemoved(_ index: Int) {
        guard index != FileTree.root, !nodes[index].flags.contains(.removed) else { return }
        let size = nodes[index].size
        let count = nodes[index].itemCount
        nodes[index].flags.insert(.removed)
        var current = index
        while let parent = parent(of: current) {
            nodes[parent].size -= min(size, nodes[parent].size)
            nodes[parent].itemCount -= min(count, nodes[parent].itemCount)
            current = parent
        }
    }

    /// Every node index in the subtree of `index`, `index` included.
    public func subtree(of index: Int) -> [Int] {
        var result: [Int] = []
        var stack = [index]
        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: children(of: next))
        }
        return result
    }
}
