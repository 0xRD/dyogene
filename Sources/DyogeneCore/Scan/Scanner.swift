import Darwin
import Foundation
import Synchronization

/// A first-level folder finished scanning: lets the map grow while the scan runs.
public struct SettledItem: Sendable, Hashable {
    public let name: String
    public let size: UInt64
    public let lastUsed: Double
    public let kind: Kind
}

/// Counters the UI reads while a scan runs. Thread safe.
public final class ScanProgress: Sendable {
    private let files = Atomic<UInt64>(0)
    private let bytes = Atomic<UInt64>(0)
    private let folders = Atomic<UInt64>(0)
    private let settledItems = Mutex<[SettledItem]>([])

    public init() {}

    public var fileCount: UInt64 { files.load(ordering: .relaxed) }
    public var byteCount: UInt64 { bytes.load(ordering: .relaxed) }
    public var folderCount: UInt64 { folders.load(ordering: .relaxed) }
    public var settled: [SettledItem] { settledItems.withLock { $0 } }

    func add(files count: UInt64, bytes size: UInt64) {
        files.add(count, ordering: .relaxed)
        bytes.add(size, ordering: .relaxed)
    }
    func addFolder() { folders.add(1, ordering: .relaxed) }
    func settle(_ item: SettledItem) { settledItems.withLock { $0.append(item) } }
}

public struct ScanOptions: Sendable {
    public var root: String
    /// Files at least this big are always kept as their own node.
    public var keepFilesAbove: UInt64 = 512 * 1024
    /// The largest files of each folder are kept whatever their size.
    public var keepLargestFiles = 16
    /// Absolute paths never entered.
    public var exclusions: [String] = []
    /// Absolute paths macOS guards behind a permission prompt; skipped and marked `needsAccess`.
    public var protected: [String] = []

    /// `protectedSkips` defaults to the usual protected folders when Full Disk Access is missing:
    /// opening them would block on a permission prompt or fail anyway.
    public init(root: String, exclusions: [String] = [], protectedSkips: [String]? = nil) {
        self.root = (root as NSString).standardizingPath
        self.exclusions = exclusions.map { ($0 as NSString).standardizingPath }
        self.protected = protectedSkips ?? (FullDiskAccess.isGranted ? [] : ScanOptions.protectedFolders(home: NSHomeDirectory()))
    }

    /// Folders of a home that macOS shows only with Full Disk Access, or after a prompt per app
    /// ("would like to access data from other apps"). Desktop, Documents and Downloads are not
    /// listed: their one-time prompt is expected.
    public static func protectedFolders(home: String) -> [String] {
        let relative = [
            "Library/Containers", "Library/Group Containers", "Library/Mobile Documents", "Library/Mail",
            "Library/Messages", "Library/Safari", "Library/Calendars", "Library/Reminders", "Library/HomeKit",
            "Library/Cookies", "Library/Suggestions", "Library/Biome", "Library/Daemon Containers",
            "Library/IdentityServices", "Library/Metadata/CoreSpotlight", "Library/Accounts", "Library/Sharing",
            "Library/PersonalizationPortrait", "Library/DuetExpertCenter", "Library/Trial", "Library/Weather",
            "Library/Application Support/AddressBook", "Library/Application Support/CallHistoryDB",
            "Library/Application Support/com.apple.TCC", "Library/Application Support/Knowledge",
            "Library/Application Support/MobileSync", "Library/Application Support/FileProvider",
            "Library/Application Support/com.apple.sharedfilelist", "Library/CloudStorage", ".Trash",
        ]
        return relative.map { (home as NSString).appendingPathComponent($0) }
    }
}

/// Walks a folder in parallel and builds a `FileTree`. Reads metadata only; never follows
/// symlinks, never enters other volumes, never downloads iCloud placeholders.
public struct Scanner: Sendable {
    public let options: ScanOptions
    public let progress: ScanProgress

    public init(options: ScanOptions, progress: ScanProgress = ScanProgress()) {
        self.options = options
        self.progress = progress
    }

    public enum Failure: Error, CustomStringConvertible {
        case notAFolder(String)
        case cannotRead(String)

        public var description: String {
            switch self {
            case .notAFolder(let path): "\(path) is not a folder."
            case .cannotRead(let path): "Dyogène cannot read \(path). Check its permissions or Full Disk Access."
            }
        }
    }

    public func scan() async throws -> FileTree {
        Scanner.refuseMaterialization()
        let root = options.root
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.notAFolder(root)
        }
        guard let device = DirectoryReader.device(of: root) else { throw Failure.cannotRead(root) }
        let context = Context(device: device, options: options, progress: progress)
        let name = root == "/" ? "/" : (root as NSString).lastPathComponent
        let result = await Scanner.scanFolder(path: root, name: name, modified: 0, parentName: nil, depth: 0, context: context)
        try Task.checkCancellation()
        if result.flags.contains(.unreadable) { throw Failure.cannotRead(root) }
        return TreeBuilder.build(root: result, rootPath: root, scannedAt: Date())
    }

    /// Asks the kernel never to download dataless (iCloud) files for this process, so a scan
    /// can never trigger network traffic or fill the disk.
    static func refuseMaterialization() {
        // IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES = 3, IOPOL_SCOPE_PROCESS = 0, IOPOL_MATERIALIZE_DATALESS_FILES_OFF = 1
        _ = setiopolicy_np(3, 0, 1)
    }

    final class Context: Sendable {
        let device: Int32
        let options: ScanOptions
        let progress: ScanProgress
        let seenHardLinks = Mutex<Set<UInt64>>([])
        let exclusions: Set<String>
        let protected: Set<String>

        init(device: Int32, options: ScanOptions, progress: ScanProgress) {
            self.device = device
            self.options = options
            self.progress = progress
            self.exclusions = Set(options.exclusions)
            self.protected = Set(options.protected)
        }

        /// True the first time a hard-linked file is seen.
        func firstSighting(of fileID: UInt64) -> Bool {
            seenHardLinks.withLock { $0.insert(fileID).inserted }
        }
    }

    static func scanFolder(path: String, name: String, modified: Double, parentName: String?, depth: Int,
                           context: Context) async -> ScannedFolder {
        var folder = ScannedFolder(name: name, flags: [.directory])
        if KindClassifier.isPackage(directoryName: name) { folder.flags.insert(.package) }
        if Task.isCancelled { return folder }
        context.progress.addFolder()

        guard let entries = await readOffThePool(path) else {
            folder.flags.insert(.unreadable)
            return folder
        }

        var files: [ScannedFile] = []
        var subfolders: [(path: String, name: String, modified: Double)] = []
        var fileBytes: UInt64 = 0
        for entry in entries {
            let childPath = path == "/" ? "/" + entry.name : path + "/" + entry.name
            switch entry.type {
            case .directory:
                if entry.device != context.device {
                    var mount = ScannedFolder(name: entry.name, flags: [.directory, .mountPoint])
                    mount.lastUsed = entry.modified
                    folder.folders.append(mount)
                } else if entry.flags & DirectoryReader.datalessFlag != 0 {
                    // Listing it would ask iCloud for its content.
                    var cloud = ScannedFolder(name: entry.name, flags: [.directory, .inCloud])
                    cloud.lastUsed = entry.modified
                    folder.folders.append(cloud)
                } else if context.exclusions.contains(childPath) {
                    continue
                } else if context.protected.contains(childPath) {
                    var guarded = ScannedFolder(name: entry.name, flags: [.directory, .needsAccess])
                    guarded.lastUsed = entry.modified
                    folder.folders.append(guarded)
                } else {
                    subfolders.append((childPath, entry.name, entry.modified))
                }
            case .file, .symlink:
                var flags: NodeFlags = entry.type == .symlink ? [.symlink] : []
                var size = entry.allocatedSize
                if entry.flags & DirectoryReader.datalessFlag != 0 {
                    flags.insert(.inCloud)
                    size = 0
                }
                if entry.type == .file, entry.linkCount > 1, !context.firstSighting(of: entry.fileID) {
                    flags.insert(.hardLink)
                    size = 0
                }
                fileBytes += size
                files.append(ScannedFile(name: entry.name, size: size, lastUsed: max(entry.modified, entry.accessed),
                                         kind: KindClassifier.kind(ofFile: entry.name), flags: flags, count: 1))
            case .other:
                continue
            }
        }
        context.progress.add(files: UInt64(files.count), bytes: fileBytes)
        folder.files = prune(files, options: context.options)
        // Used only when the folder holds nothing dated: an empty folder is as old as its last change.
        folder.lastUsed = modified

        let children = await withTaskGroup(of: ScannedFolder.self) { group in
            for sub in subfolders {
                group.addTask {
                    let scanned = await scanFolder(path: sub.path, name: sub.name, modified: sub.modified, parentName: name, depth: depth + 1, context: context)
                    if depth == 0 {
                        context.progress.settle(SettledItem(name: sub.name, size: scanned.size,
                                                            lastUsed: scanned.lastUsed, kind: scanned.kind))
                    }
                    return scanned
                }
            }
            var collected: [ScannedFolder] = []
            collected.reserveCapacity(subfolders.count)
            for await child in group { collected.append(child) }
            return collected
        }
        folder.folders.append(contentsOf: children)
        folder.finish(parentName: parentName)
        return folder
    }

    /// Directory reads can block for a long time (a permission prompt, a slow disk). They run on
    /// their own threads so they never hold the Swift concurrency pool.
    private static let ioQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Dyogene scan"
        queue.maxConcurrentOperationCount = min(12, max(4, ProcessInfo.processInfo.activeProcessorCount))
        queue.qualityOfService = .userInitiated
        return queue
    }()

    static func readOffThePool(_ path: String) async -> [RawEntry]? {
        await withCheckedContinuation { continuation in
            ioQueue.addOperation {
                continuation.resume(returning: try? DirectoryReader.read(path))
            }
        }
    }

    /// Keeps big files as nodes and folds the many small ones into one group per folder.
    static func prune(_ files: [ScannedFile], options: ScanOptions) -> [ScannedFile] {
        guard files.count > options.keepLargestFiles else { return files }
        let sorted = files.sorted { $0.size > $1.size }
        var kept: [ScannedFile] = []
        var group = ScannedFile(name: "", size: 0, lastUsed: 0, kind: .other, flags: [.smallGroup], count: 0)
        var kindBytes: [Kind: UInt64] = [:]
        for (i, file) in sorted.enumerated() {
            if i < options.keepLargestFiles || file.size >= options.keepFilesAbove {
                kept.append(file)
            } else {
                group.size += file.size
                group.count += 1
                group.lastUsed = max(group.lastUsed, file.lastUsed)
                kindBytes[file.kind, default: 0] += max(file.size, 1)
            }
        }
        if group.count > 0 {
            group.kind = kindBytes.max { $0.value < $1.value }?.key ?? .other
            group.name = group.count == 1 ? "1 small file" : "\(group.count) small files"
            kept.append(group)
        }
        return kept
    }
}

struct ScannedFile: Sendable {
    var name: String
    var size: UInt64
    var lastUsed: Double
    var kind: Kind
    var flags: NodeFlags
    var count: UInt64
}

struct ScannedFolder: Sendable {
    var name: String
    var flags: NodeFlags
    var lastUsed: Double = 0
    var files: [ScannedFile] = []
    var folders: [ScannedFolder] = []
    // Totals, filled by `finish` once the children are done.
    var size: UInt64 = 0
    var count: UInt64 = 0
    var kind: Kind = .other

    /// Adds up the children (already finished) and picks the folder's kind.
    mutating func finish(parentName: String?) {
        var size: UInt64 = 0
        var count: UInt64 = 0
        var newest = 0.0
        var kindBytes: [Kind: UInt64] = [:]
        for file in files {
            size += file.size
            count += file.count
            newest = max(newest, file.lastUsed)
            kindBytes[file.kind, default: 0] += file.size
        }
        for folder in folders {
            size += folder.size
            count += folder.count
            newest = max(newest, folder.lastUsed)
            kindBytes[folder.kind, default: 0] += folder.size
        }
        self.size = size
        self.count = count
        if newest > 0 { lastUsed = newest }
        if let own = KindClassifier.kind(ofDirectory: name, parentName: parentName) {
            kind = own
        } else if let dominant = kindBytes.max(by: { $0.value < $1.value }), dominant.value > 0,
                  Double(dominant.value) >= 0.5 * Double(size) {
            kind = dominant.key
        } else {
            kind = .other
        }
    }
}
