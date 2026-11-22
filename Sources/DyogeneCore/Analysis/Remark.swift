import Foundation

/// What Dyogène, the old sage of the app, says about an item. Built from metadata only (size,
/// age, kind, flags), never from contents. Wry, short, never a verdict: the user decides.
public struct Remark: Sendable, Equatable {
    public enum Mood: Sendable, Equatable {
        case calm, curious, pleased, searching
    }

    public let text: String
    public let mood: Mood

    public init(_ text: String, mood: Mood) {
        self.text = text
        self.mood = mood
    }

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso", "ipsw"]
    private static let rebuildable: Set<String> = ["node_modules", ".build", "DerivedData", "__pycache__", "Pods", ".gradle"]

    public static func about(_ index: Int, in tree: FileTree, now: Double) -> Remark {
        let node = tree[index]
        let age = node.lastUsed > 0 ? now - node.lastUsed : 0
        let ageText = Format.age(lastUsed: node.lastUsed, now: now)
        let size = Format.bytes(node.size)

        if index == FileTree.root {
            return Remark("\(size), and I have only a jar. Hover a tile and I will hold up my lantern.", mood: .calm)
        }
        if node.flags.contains(.needsAccess) {
            return Remark("A locked door. Give me Full Disk Access and I will look behind it.", mood: .curious)
        }
        if node.flags.contains(.unreadable) {
            return Remark("This one keeps its door shut, even to me.", mood: .curious)
        }
        if node.flags.contains(.inCloud) {
            return Remark("Up in the clouds, like my thoughts. It takes no room on this Mac.", mood: .pleased)
        }
        if node.flags.contains(.mountPoint) {
            return Remark("Another disk lives here. Scan it on its own.", mood: .calm)
        }
        if node.flags.contains(.smallGroup) {
            return Remark("Crumbs: \(Format.count(node.itemCount)) small files. Many crumbs still make \(size).", mood: .calm)
        }
        if node.flags.contains(.hardLink) {
            return Remark("A second name for a file I already counted.", mood: .calm)
        }
        if rebuildable.contains(node.name) {
            return Remark("Build leftovers. One command makes them again, so they weigh less than they seem.", mood: .calm)
        }
        if node.kind == .cache {
            return Remark("Apps keep this to go faster. They will make it again if it goes.", mood: .calm)
        }
        let ext = (node.name as NSString).pathExtension.lowercased()
        if installerExtensions.contains(ext) {
            return Remark("An installer. Once the app is in, the box can go.", mood: .curious)
        }
        if node.size >= 5_000_000_000 && age >= 2 * 365 * Dust.day {
            return Remark("\(size), untouched for \(ageText.replacingOccurrences(of: " ago", with: "")). Treasure, or habit?", mood: .curious)
        }
        if node.size >= 500_000_000 && age >= 365 * Dust.day {
            return Remark("Nobody has opened this for \(ageText.replacingOccurrences(of: " ago", with: "")). Do you still need it?", mood: .curious)
        }
        if node.lastUsed > 0 && age < 30 * Dust.day {
            return Remark("Used \(ageText). This one still earns its place.", mood: .pleased)
        }
        if node.isDirectory && !node.isPackage {
            return Remark("\(Format.count(node.itemCount)) files live here. Look inside before judging.", mood: .calm)
        }
        return Remark("\(size), last used \(ageText).", mood: .calm)
    }
}
