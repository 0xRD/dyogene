import Foundation

/// Flattens a scanned folder into a `FileTree`: breadth first, so the children of a folder are
/// contiguous, and sorted largest first.
enum TreeBuilder {
    static func build(root: ScannedFolder, rootPath: String, scannedAt: Date) -> FileTree {
        var nodes: [Node] = []
        nodes.reserveCapacity(4096)
        var unreadable = 0
        nodes.append(node(for: root, parent: -1))

        // Each queued folder is flattened when its node index is known.
        var queue: [(folder: ScannedFolder, index: Int)] = [(root, 0)]
        var head = 0
        while head < queue.count {
            let (folder, index) = queue[head]
            queue[head].folder = ScannedFolder(name: "", flags: []) // release memory early
            head += 1
            if folder.flags.contains(.unreadable) { unreadable += 1 }

            enum Child { case file(ScannedFile), folder(ScannedFolder) }
            var children: [(size: UInt64, child: Child)] = folder.files.map { ($0.size, .file($0)) }
            children += folder.folders.map { ($0.size, .folder($0)) }
            children.sort { $0.size > $1.size }

            nodes[index].firstChild = Int32(nodes.count)
            nodes[index].childCount = Int32(children.count)
            for (_, child) in children {
                switch child {
                case .file(let file):
                    nodes.append(Node(name: file.name, size: file.size, lastUsed: file.lastUsed, itemCount: file.count,
                                      parent: Int32(index), kind: file.kind, flags: file.flags))
                case .folder(let sub):
                    let subIndex = nodes.count
                    nodes.append(node(for: sub, parent: index))
                    queue.append((sub, subIndex))
                }
            }
            if head > 4096 {
                queue.removeFirst(head)
                head = 0
            }
        }
        return FileTree(rootPath: rootPath, scannedAt: scannedAt, nodes: nodes, unreadableCount: unreadable)
    }

    private static func node(for folder: ScannedFolder, parent: Int) -> Node {
        Node(name: folder.name, size: folder.size, lastUsed: folder.lastUsed, itemCount: folder.count,
             parent: Int32(parent), kind: folder.kind, flags: folder.flags)
    }
}
