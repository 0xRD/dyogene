import Foundation

/// Decides which paths Dyogène may ever remove, whatever the user clicks. Removing any of these
/// would break macOS, an app, or the user's account; Finder can still do it if really wanted.
public enum RemovalPolicy {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    /// Folders that are never removed themselves, nor anything inside them.
    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/private", "/dev", "/cores", "/etc", "/var", "/tmp",
                                 "/Library/Apple", "/System/Volumes"]
    /// Inside these, `/usr/local` (Homebrew) is still allowed.
    static let systemExceptions = ["/usr/local"]

    /// Standard folders of a home that stay, even if their content may go.
    static let homeFolders = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public",
                              "Applications", "Sites", ".Trash", "Library/Mobile Documents", "Library/CloudStorage",
                              "Library/Application Support", "Library/Containers", "Library/Group Containers",
                              "Library/Preferences", "Library/Keychains", "Library/Caches", "Library/Developer",
                              "Library/Mail", "Library/Messages", "Library/Photos"]

    /// Folders that must stay but whose content is fair game.
    static let keptRoots = ["/", "/Applications", "/Library", "/Users", "/Volumes", "/opt", "/opt/homebrew", "/usr/local"]

    public static func verdict(for path: String, home: String) -> Verdict {
        var path = (path as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        guard path.hasPrefix("/") else { return .refused("Not an absolute path.") }

        // The data volume seen through its mount point holds the same files as their usual paths.
        let dataVolume = "/System/Volumes/Data"
        if path == dataVolume { return .refused("This is the volume that holds your data.") }
        if path.hasPrefix(dataVolume + "/") { path = String(path.dropFirst(dataVolume.count)) }

        if keptRoots.contains(path) { return .refused("\(path) is part of the layout of macOS.") }
        if path == home { return .refused("This is your home folder.") }
        for folder in homeFolders where path == home + "/" + folder {
            return .refused("\(folder) is a standard folder of your account. Its content can be removed, not the folder.")
        }
        if !systemExceptions.contains(where: { path.hasPrefix($0 + "/") }) {
            for prefix in systemPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
                return .refused("\(prefix) belongs to macOS.")
            }
        }
        if path == "/Applications/Safari.app" || path == "/Applications/Utilities" {
            return .refused("This ships with macOS.")
        }
        if path.hasPrefix("/Volumes/"), path.dropFirst("/Volumes/".count).split(separator: "/").count == 1 {
            return .refused("This is a mounted volume. Eject it from Finder instead.")
        }
        if path.hasPrefix("/Users/"), !path.hasPrefix(home + "/") {
            return .refused("This belongs to another user account.")
        }
        return .allowed
    }

    /// Extra warnings shown before removing, without refusing.
    public static func warnings(for path: String, home: String, isInCloud: Bool) -> [String] {
        var notes: [String] = []
        let home = (home as NSString).standardizingPath
        if path.hasPrefix(home + "/Library/Mobile Documents") || path.hasPrefix(home + "/Library/CloudStorage") || isInCloud {
            notes.append("This is in a cloud folder. Removing it here removes it from your other devices too.")
        }
        if path.hasPrefix(home + "/Library/") {
            notes.append("This is app data. Quit the app it belongs to first; some apps may lose settings or content.")
        }
        if path.hasSuffix(".app") || path.hasPrefix("/Applications/") {
            notes.append("Removing an app leaves its data in your Library. The app must not be running.")
        }
        return notes
    }
}
