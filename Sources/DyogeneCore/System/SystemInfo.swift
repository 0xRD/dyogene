import CoreServices
import Darwin
import Foundation

/// Space on the volume that holds a path.
public struct VolumeUsage: Sendable, Codable, Equatable {
    public var name: String
    public var total: UInt64
    /// Free right now.
    public var free: UInt64
    /// Free once macOS purges what it can (caches, local snapshots...).
    public var freeForImportantUse: UInt64

    public init(name: String, total: UInt64, free: UInt64, freeForImportantUse: UInt64) {
        self.name = name
        self.total = total
        self.free = free
        self.freeForImportantUse = freeForImportantUse
    }

    public var used: UInt64 { total - min(total, free) }
    public var purgeable: UInt64 { freeForImportantUse > free ? freeForImportantUse - free : 0 }

    public static func of(_ path: String) -> VolumeUsage? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacity else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? UInt64(free)
        return VolumeUsage(name: values.volumeLocalizedName ?? "Disk", total: UInt64(total), free: UInt64(free),
                           freeForImportantUse: important)
    }
}

/// Whether Dyogène was given Full Disk Access in System Settings. Checked by opening (not
/// reading) a file only readable with that access.
public enum FullDiskAccess {
    public static var isGranted: Bool {
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(probe, O_RDONLY | O_CLOEXEC)
        if fd >= 0 {
            close(fd)
            return true
        }
        return false
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

/// When a file was last opened, as Spotlight recorded it. Asked one file at a time and only for
/// what is on screen: it is slower than the file system dates.
public enum LastUsed {
    public enum Source: String, Sendable, Codable {
        /// Spotlight saw it opened (kMDItemLastUsedDate).
        case spotlight
        /// Newest of the file's access and modification dates.
        case fileSystem

        public var title: String {
            switch self {
            case .spotlight: "last opened (Spotlight)"
            case .fileSystem: "last read or changed (file system)"
            }
        }
    }

    public static func spotlightDate(for path: String) -> Double? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        guard CFGetTypeID(value) == CFDateGetTypeID() else { return nil }
        let date = unsafeDowncast(value, to: CFDate.self) as Date
        return date.timeIntervalSince1970
    }

    /// The best date for a node: Spotlight's when it is newer, the scan's otherwise.
    public static func best(path: String, scanned: Double) -> (date: Double, source: Source) {
        if let spotlight = spotlightDate(for: path), spotlight > scanned {
            return (spotlight, .spotlight)
        }
        return (scanned, .fileSystem)
    }
}
