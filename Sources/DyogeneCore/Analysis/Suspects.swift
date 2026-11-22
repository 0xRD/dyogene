import Foundation

/// Usual places where space can be reclaimed, described honestly with what removing them costs.
public enum Risk: Int, Sendable, Codable, Comparable, CaseIterable {
    case low, medium, high

    public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .low: "Low risk"
        case .medium: "Check first"
        case .high: "Careful"
        }
    }

    public var key: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

public struct SuspectRule: Sendable, Identifiable {
    public enum Match: Sendable {
        /// Paths relative to the home folder.
        case homePaths([String])
        /// Every folder with this name, anywhere (the outermost one only).
        case folderNamed(String)
        /// Files with these extensions inside a home-relative folder.
        case extensions([String], inHomePath: String)
        /// Top-level items of a home-relative folder unused for this long (seconds).
        case unusedItems(inHomePath: String, olderThan: Double)
        /// Files with this exact name anywhere.
        case fileNamed(String)
    }

    public let id: String
    public let title: String
    /// What it is.
    public let explanation: String
    /// What happens if you remove it.
    public let consequence: String
    /// A better way to clean it than deleting by hand, when there is one.
    public let advice: String?
    public let risk: Risk
    public let match: Match
}

public struct SuspectFinding: Sendable, Identifiable {
    public var id: String { rule.id }
    public let rule: SuspectRule
    /// Matching nodes, largest first.
    public let nodes: [Int]
    public let size: UInt64
}

public enum Suspects {
    public static let rules: [SuspectRule] = [
        SuspectRule(
            id: "trash", title: "Trash",
            explanation: "Files you already threw away. They still use space until the Trash is emptied.",
            consequence: "Gone for good once emptied.",
            advice: "Empty it from Finder when you are sure.",
            risk: .low, match: .homePaths([".Trash"])),
        SuspectRule(
            id: "installers", title: "Installers in Downloads",
            explanation: "Disk images, packages and archives you downloaded. Once the app is installed, the installer is rarely needed.",
            consequence: "You would download them again if you need to reinstall.",
            advice: nil,
            risk: .low, match: .extensions(["dmg", "pkg", "mpkg", "zip", "xip", "iso", "rar", "7z", "ipsw"], inHomePath: "Downloads")),
        SuspectRule(
            id: "user-caches", title: "App caches",
            explanation: "Data apps keep to go faster: thumbnails, downloaded updates, web caches. Apps rebuild them when needed.",
            consequence: "Some apps start slower the first time and may sign you out of web views.",
            advice: "Quit the apps first. Homebrew's part is cleaned with brew cleanup.",
            risk: .low, match: .homePaths(["Library/Caches"])),
        SuspectRule(
            id: "xcode-derived-data", title: "Xcode build data",
            explanation: "Intermediate build products of Xcode projects (DerivedData).",
            consequence: "The next build of each project takes longer.",
            advice: nil,
            risk: .low, match: .homePaths(["Library/Developer/Xcode/DerivedData"])),
        SuspectRule(
            id: "xcode-device-support", title: "Xcode device support files",
            explanation: "Debug symbols copied from every iPhone, iPad or Watch version you ever connected.",
            consequence: "Xcode copies them again the next time you debug on that device.",
            advice: nil,
            risk: .low, match: .homePaths(["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport"])),
        SuspectRule(
            id: "node-modules", title: "node_modules folders",
            explanation: "JavaScript dependencies installed by npm, yarn or pnpm for each project.",
            consequence: "Run the install command again before working on that project.",
            advice: nil,
            risk: .low, match: .folderNamed("node_modules")),
        SuspectRule(
            id: "swift-build", title: "Swift and other .build folders",
            explanation: "Build products of SwiftPM and similar tools, one per project.",
            consequence: "The next build of that project starts from scratch.",
            advice: nil,
            risk: .low, match: .folderNamed(".build")),
        SuspectRule(
            id: "old-downloads", title: "Downloads untouched for 6 months",
            explanation: "Items of your Downloads folder nobody opened or changed in half a year.",
            consequence: "Look at them first: some downloads are the only copy of a document.",
            advice: nil,
            risk: .medium, match: .unusedItems(inHomePath: "Downloads", olderThan: 182 * Dust.day)),
        SuspectRule(
            id: "simulators", title: "iOS simulators",
            explanation: "Simulated devices of Xcode with the apps and data installed on them.",
            consequence: "Apps and data inside those simulators are lost.",
            advice: "Prefer `xcrun simctl delete unavailable` and Xcode's Devices window.",
            risk: .medium, match: .homePaths(["Library/Developer/CoreSimulator/Devices", "Library/Developer/CoreSimulator/Caches"])),
        SuspectRule(
            id: "xcode-archives", title: "Xcode archives",
            explanation: "Builds you archived for distribution.",
            consequence: "Without them you cannot read crash reports of the versions you shipped.",
            advice: "Keep the archives of versions still in use.",
            risk: .medium, match: .homePaths(["Library/Developer/Xcode/Archives"])),
        SuspectRule(
            id: "docker", title: "Container and VM disks",
            explanation: "Disk images of Docker, OrbStack or other virtual machines. They grow and rarely shrink by themselves.",
            consequence: "Containers, images and volumes inside are lost.",
            advice: "Prune from the tool itself (docker system prune, OrbStack settings) instead of deleting the file.",
            risk: .medium, match: .fileNamed("Docker.raw")),
        SuspectRule(
            id: "ios-backups", title: "iPhone and iPad backups",
            explanation: "Local backups made by Finder when a device is connected.",
            consequence: "This may be the only backup of a device. Delete only backups of devices you no longer have or that back up to iCloud.",
            advice: "Manage them from Finder: select the device, then Manage Backups.",
            risk: .high, match: .homePaths(["Library/Application Support/MobileSync/Backup"])),
        SuspectRule(
            id: "ios-updates", title: "Device software updates",
            explanation: "Firmware files downloaded to update or restore iPhones and iPads.",
            consequence: "Downloaded again when needed.",
            advice: nil,
            risk: .low, match: .homePaths(["Library/iTunes/iPhone Software Updates", "Library/iTunes/iPad Software Updates"])),
        SuspectRule(
            id: "mail-downloads", title: "Mail attachments opened",
            explanation: "Copies of attachments you opened from Mail.",
            consequence: "The originals stay in your mailbox.",
            advice: nil,
            risk: .low, match: .homePaths(["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"])),
    ]

    /// Runs every rule on the tree. `home` is the home folder; rules using home paths only match
    /// when the scan covers it.
    public static func findings(in tree: FileTree, home: String, now: Double) -> [SuspectFinding] {
        var claimed = Set<Int>()
        var results: [SuspectFinding] = []
        for rule in rules {
            let matched = nodes(for: rule.match, in: tree, home: home, now: now)
                .filter { index in
                    // A node already counted by an earlier rule, or inside one, is not counted twice.
                    !claimed.contains(index) && !tree.lineage(of: index).contains(where: claimed.contains)
                }
                .filter { tree[$0].size > 0 && !tree[$0].flags.contains(.removed) }
                .sorted { tree[$0].size > tree[$1].size }
            guard !matched.isEmpty else { continue }
            claimed.formUnion(matched)
            results.append(SuspectFinding(rule: rule, nodes: matched,
                                          size: matched.reduce(0) { $0 + tree[$1].size }))
        }
        return results.sorted { a, b in a.size > b.size }
    }

    static func nodes(for match: SuspectRule.Match, in tree: FileTree, home: String, now: Double) -> [Int] {
        func homeNode(_ relative: String) -> Int? {
            tree.index(ofPath: (home as NSString).appendingPathComponent(relative))
        }
        switch match {
        case .homePaths(let paths):
            return paths.compactMap(homeNode)
        case .folderNamed(let name):
            return outermost(in: tree) { $0.isDirectory && $0.name == name }
        case .fileNamed(let name):
            return outermost(in: tree) { !$0.isDirectory && $0.name == name }
        case .extensions(let list, let folder):
            guard let start = homeNode(folder) else { return [] }
            let wanted = Set(list)
            return tree.subtree(of: start).filter { index in
                let node = tree[index]
                guard node.isActionable, !node.isDirectory || node.isPackage else { return false }
                let ext = (node.name as NSString).pathExtension.lowercased()
                return wanted.contains(ext) && !tree.lineage(of: index).dropLast().contains { tree[$0].isPackage }
            }
        case .unusedItems(let folder, let age):
            guard let start = homeNode(folder) else { return [] }
            return tree.children(of: start).filter { index in
                let node = tree[index]
                return node.isActionable && node.lastUsed > 0 && now - node.lastUsed >= age
            }
        }
    }

    /// Nodes matching `predicate` that are not inside another match.
    private static func outermost(in tree: FileTree, where predicate: (Node) -> Bool) -> [Int] {
        var result: [Int] = []
        var stack = [FileTree.root]
        while let index = stack.popLast() {
            let node = tree[index]
            if index != FileTree.root && predicate(node) {
                result.append(index)
                continue
            }
            if node.isDirectory { stack.append(contentsOf: tree.children(of: index)) }
        }
        return result
    }
}
