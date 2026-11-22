import Foundation

/// JSON shapes printed by the `dyogene` CLI. Metadata only: names, sizes, dates, kinds.
public enum Report {
    public struct Entry: Codable, Sendable {
        public let path: String
        public let name: String
        public let type: String
        public let size: UInt64
        public let sizeText: String
        public let lastUsed: String
        public let lastUsedAge: String
        public let kind: String
        public let items: UInt64
        public var children: [Entry]?
    }

    public struct KindShare: Codable, Sendable {
        public let kind: String
        public let size: UInt64
        public let sizeText: String
    }

    public struct AgeShare: Codable, Sendable {
        public let unusedFor: String
        public let size: UInt64
        public let sizeText: String
    }

    public struct Volume: Codable, Sendable {
        public let name: String
        public let total: String
        public let used: String
        public let free: String
        public let purgeable: String
    }

    public struct Summary: Codable, Sendable {
        public let scannedFolder: String
        public let scannedAt: String
        public let scannedSize: String
        public let scannedBytes: UInt64
        public let files: UInt64
        public let unreadableFolders: Int
        public let fullDiskAccess: Bool
        public let volume: Volume?
        public let notSeenByScan: String?
        public let byKind: [KindShare]
        public let byAge: [AgeShare]
        public let largestFolders: [Entry]
    }

    public struct Suspect: Codable, Sendable {
        public let id: String
        public let title: String
        public let risk: String
        public let size: UInt64
        public let sizeText: String
        public let explanation: String
        public let consequence: String
        public let advice: String?
        public let locations: [Entry]
    }

    public struct Full: Codable, Sendable {
        public let note: String
        public let summary: Summary
        public let largestItems: [Entry]
        public let foldersOfFiles: [Entry]
        public let unusedForAYear: [Entry]
        public let suspects: [Suspect]
    }

    public static let privacyNote = "Metadata only (names, sizes, dates). File contents were not read. Paths can be personal: do not share them outside this conversation."

    public static func entry(_ index: Int, in tree: FileTree, now: Double, depth: Int = 0) -> Entry {
        let node = tree[index]
        let type: String = node.flags.contains(.smallGroup) ? "group-of-small-files"
            : node.isPackage ? "package" : node.isDirectory ? "folder" : node.flags.contains(.symlink) ? "symlink" : "file"
        var entry = Entry(path: tree.displayPath(of: index), name: node.name, type: type, size: node.size,
                          sizeText: Format.bytes(node.size), lastUsed: Format.date(node.lastUsed),
                          lastUsedAge: Format.age(lastUsed: node.lastUsed, now: now), kind: node.kind.key,
                          items: node.itemCount, children: nil)
        if depth > 0, node.isDirectory {
            entry.children = tree.visibleChildren(of: index).prefix(25).map { self.entry($0, in: tree, now: now, depth: depth - 1) }
        }
        return entry
    }

    public static func summary(of tree: FileTree, volume: VolumeUsage?, fullDiskAccess: Bool, now: Double) -> Summary {
        var kinds: [Kind: UInt64] = [:]
        var ages = [UInt64](repeating: 0, count: 5)
        let limits: [Double] = [30, 182, 365, 3 * 365].map { $0 * Dust.day }
        // Each byte counted once: stop at files, groups and packages.
        var stack = [FileTree.root]
        while let index = stack.popLast() {
            let node = tree[index]
            if node.flags.contains(.removed) { continue }
            if node.isDirectory && !node.isPackage {
                stack.append(contentsOf: tree.children(of: index))
                continue
            }
            kinds[node.kind, default: 0] += node.size
            let age = node.lastUsed > 0 ? now - node.lastUsed : 0
            ages[limits.firstIndex { age < $0 } ?? 4] += node.size
        }
        let ageLabels = ["less than 1 month", "1 to 6 months", "6 to 12 months", "1 to 3 years", "3 years or more"]
        let byKind = kinds.filter { $0.value > 0 }.sorted { $0.value > $1.value }
            .map { KindShare(kind: $0.key.key, size: $0.value, sizeText: Format.bytes($0.value)) }
        let byAge = zip(ageLabels, ages).map { AgeShare(unusedFor: $0, size: $1, sizeText: Format.bytes($1)) }
        let largest = Hoard.items(in: tree, filter: .init(mode: .folders, limit: 15), now: now)
        let volumeReport = volume.map {
            Volume(name: $0.name, total: Format.bytes($0.total), used: Format.bytes($0.used), free: Format.bytes($0.free),
                   purgeable: Format.bytes($0.purgeable))
        }
        let notSeen = volume.map { Format.bytes($0.used > tree.totalSize ? $0.used - tree.totalSize : 0) }
        return Summary(scannedFolder: tree.rootPath == FileTree.dataVolume ? "/ (whole Mac, data volume)" : tree.rootPath, scannedAt: ISO8601DateFormatter().string(from: tree.scannedAt),
                       scannedSize: Format.bytes(tree.totalSize), scannedBytes: tree.totalSize, files: tree[0].itemCount,
                       unreadableFolders: tree.unreadableCount, fullDiskAccess: fullDiskAccess, volume: volumeReport,
                       notSeenByScan: notSeen, byKind: byKind, byAge: byAge,
                       largestFolders: largest.map { entry($0, in: tree, now: now) })
    }

    public static func suspects(in tree: FileTree, home: String, now: Double) -> [Suspect] {
        Suspects.findings(in: tree, home: home, now: now).map { finding in
            Suspect(id: finding.rule.id, title: finding.rule.title, risk: finding.rule.risk.key, size: finding.size,
                    sizeText: Format.bytes(finding.size), explanation: finding.rule.explanation,
                    consequence: finding.rule.consequence, advice: finding.rule.advice,
                    locations: finding.nodes.prefix(10).map { entry($0, in: tree, now: now) })
        }
    }

    public static func full(tree: FileTree, volume: VolumeUsage?, fullDiskAccess: Bool, home: String, now: Double) -> Full {
        Full(note: privacyNote,
             summary: summary(of: tree, volume: volume, fullDiskAccess: fullDiskAccess, now: now),
             largestItems: Hoard.items(in: tree, filter: .init(mode: .items, limit: 25), now: now).map { entry($0, in: tree, now: now) },
             foldersOfFiles: Hoard.items(in: tree, filter: .init(mode: .folders, limit: 15), now: now).map { entry($0, in: tree, now: now) },
             unusedForAYear: Hoard.items(in: tree, filter: .init(mode: .items, unusedFor: 365 * Dust.day, minimumSize: 100_000_000, limit: 25), now: now)
                .map { entry($0, in: tree, now: now) },
             suspects: suspects(in: tree, home: home, now: now))
    }

    public static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
