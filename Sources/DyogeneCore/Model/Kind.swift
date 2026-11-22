import Foundation

/// A coarse family of content, guessed from names only (never from file contents).
public enum Kind: UInt8, Sendable, Codable, CaseIterable, Hashable {
    case other
    case video
    case photo
    case audio
    case app
    case archive
    case virtualDisk
    case developer
    case cache
    case document

    public var title: String {
        switch self {
        case .other: "Other"
        case .video: "Videos"
        case .photo: "Photos"
        case .audio: "Audio"
        case .app: "Apps"
        case .archive: "Archives and installers"
        case .virtualDisk: "Disk images and VMs"
        case .developer: "Developer"
        case .cache: "Caches"
        case .document: "Documents"
        }
    }

    /// JSON name used by the CLI.
    public var key: String {
        switch self {
        case .other: "other"
        case .video: "video"
        case .photo: "photo"
        case .audio: "audio"
        case .app: "app"
        case .archive: "archive"
        case .virtualDisk: "virtual-disk"
        case .developer: "developer"
        case .cache: "cache"
        case .document: "document"
        }
    }
}

/// Guesses kinds and package-ness from names.
public enum KindClassifier {
    private static let extensions: [String: Kind] = {
        var map: [String: Kind] = [:]
        func add(_ kind: Kind, _ list: String) {
            for ext in list.split(separator: " ") { map[String(ext)] = kind }
        }
        add(.video, "mp4 mov m4v mkv avi webm wmv flv mpg mpeg mts m2ts 3gp braw r3d prproj fcpbundle imovielibrary")
        add(.photo, "jpg jpeg png heic heif gif tif tiff bmp webp raw cr2 cr3 nef arw dng orf rw2 raf psd psb afphoto xcf svg photoslibrary aplibrary lrcat lrdata")
        add(.audio, "mp3 m4a m4b aac flac wav aif aiff ogg opus alac caf mid midi logicx band musiclibrary")
        add(.app, "app prefpane plugin saver qlgenerator appex")
        add(.archive, "dmg pkg mpkg zip rar 7z tar gz tgz bz2 xz zst lz4 iso xip ipa ipsw cab jar")
        add(.virtualDisk, "vmdk vdi qcow2 vhd vhdx img sparseimage sparsebundle utm vmwarevm pvm raw-disk")
        add(.developer, "o a dylib swiftmodule swiftinterface pch xcarchive xcodeproj xcworkspace dSYM gch class pyc whl crate rlib wasm")
        add(.cache, "cache")
        add(.document, "pdf doc docx pages key numbers xls xlsx ppt pptx txt md rtf rtfd epub odt ods odp csv json xml html htm tex")
        return map
    }()

    /// Directory extensions Finder shows as one item.
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "prefpane", "saver", "qlgenerator", "appex",
        "photoslibrary", "aplibrary", "musiclibrary", "imovielibrary", "fcpbundle", "logicx", "band",
        "pages", "key", "numbers", "rtfd", "xcarchive", "xcodeproj", "xcworkspace", "playground",
        "sparsebundle", "utm", "vmwarevm", "pvm", "lrdata", "dSYM", "pkg", "mpkg", "xip",
    ]

    /// Folder names that are developer artifacts wherever they are.
    private static let developerFolders: Set<String> = [
        "node_modules", "DerivedData", ".build", ".git", "CoreSimulator", "Pods", ".gradle",
        ".cargo", ".rustup", ".npm", ".pnpm-store", ".yarn", "__pycache__", ".venv", "venv",
        ".swiftpm", "Carthage", ".m2", ".nuget", "iOS DeviceSupport", "watchOS DeviceSupport",
    ]

    private static let cacheFolders: Set<String> = [".cache", "Caches", "Cache", "cache", "CachedData", "GPUCache", "Code Cache"]

    private static func ext(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }

    public static func isPackage(directoryName name: String) -> Bool {
        let e = ext(name)
        return !e.isEmpty && (packageExtensions.contains(e) || packageExtensions.contains(e.lowercased()))
    }

    public static func kind(ofFile name: String) -> Kind {
        if name == "Docker.raw" || name == "data.img" { return .virtualDisk }
        let e = ext(name)
        if e.isEmpty { return .other }
        return extensions[e] ?? extensions[e.lowercased()] ?? .other
    }

    /// The kind a folder has because of its own name, or nil when its content decides.
    public static func kind(ofDirectory name: String, parentName: String?) -> Kind? {
        if developerFolders.contains(name) { return .developer }
        if cacheFolders.contains(name) { return .cache }
        if name == "Developer" && parentName == "Library" { return .developer }
        let e = ext(name)
        if !e.isEmpty, let kind = extensions[e] ?? extensions[e.lowercased()], isPackage(directoryName: name) {
            return kind
        }
        return nil
    }
}
