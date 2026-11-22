import Darwin
import Foundation

/// The three ways Dyogène removes something. Every call re-checks `RemovalPolicy` itself, so a
/// UI bug cannot get around it.
public enum RemovalMode: String, Sendable, CaseIterable, Codable {
    /// Moved to the Trash: can be put back.
    case trash
    /// Unlinked right away: does not go through the Trash.
    case permanent
    /// Contents overwritten with random bytes before unlinking. Best effort on SSDs (see SECURITY.md).
    case secureErase

    public var title: String {
        switch self {
        case .trash: "Move to Trash"
        case .permanent: "Delete Permanently"
        case .secureErase: "Erase Securely"
        }
    }

    /// How long the confirm button must be held, in seconds.
    public var holdDuration: Double {
        switch self {
        case .trash: 1.5
        case .permanent: 2
        case .secureErase: 3
        }
    }
}

public enum FileRemover {
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case refused(String)
        case failed(String, String)

        public var description: String {
            switch self {
            case .refused(let reason): reason
            case .failed(let path, let reason): "Could not remove \((path as NSString).lastPathComponent): \(reason)"
            }
        }
    }

    public struct Outcome: Sendable, Equatable {
        public let originalPath: String
        /// Where the item went, for `trash`: lets the app put it back.
        public let trashedPath: String?
    }

    public static func remove(_ path: String, mode: RemovalMode, home: String = NSHomeDirectory()) throws -> Outcome {
        if case .refused(let reason) = RemovalPolicy.verdict(for: path, home: home) {
            throw Failure.refused(reason)
        }
        if mode != .trash, let reason = preflight(path, mode: mode) {
            throw Failure.refused(reason)
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { throw Failure.failed(path, "it no longer exists.") }

        switch mode {
        case .trash:
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
            } catch {
                throw Failure.failed(path, error.localizedDescription)
            }
            return Outcome(originalPath: path, trashedPath: resulting?.path)
        case .permanent:
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                throw Failure.failed(path, error.localizedDescription)
            }
            return Outcome(originalPath: path, trashedPath: nil)
        case .secureErase:
            try secureErase(path)
            return Outcome(originalPath: path, trashedPath: nil)
        }
    }

    /// Puts a trashed item back where it was. Refuses to overwrite anything.
    public static func putBack(_ outcome: Outcome) throws {
        guard let trashed = outcome.trashedPath else { throw Failure.failed(outcome.originalPath, "it was not in the Trash.") }
        guard !FileManager.default.fileExists(atPath: outcome.originalPath) else {
            throw Failure.failed(outcome.originalPath, "something else has taken its place.")
        }
        do {
            try FileManager.default.moveItem(atPath: trashed, toPath: outcome.originalPath)
        } catch {
            throw Failure.failed(outcome.originalPath, error.localizedDescription)
        }
    }

    /// Checks a whole folder before deleting it for good, so nothing is half done: another disk
    /// mounted inside must never be wiped through it, and a secure erase must not stop midway on
    /// a file it cannot erase. Returns why it is refused, or nil.
    public static func preflight(_ path: String, mode: RemovalMode) -> String? {
        var top = stat()
        guard lstat(path, &top) == 0 else { return nil }
        guard top.st_mode & S_IFMT == S_IFDIR else {
            if mode == .secureErase && top.st_mode & S_IFMT == S_IFREG && top.st_nlink > 1 {
                return "It has other names (hard links), so its content would survive. Use Delete Permanently."
            }
            return nil
        }
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return nil }
        while let relative = enumerator.nextObject() as? String {
            var info = stat()
            guard lstat(path + "/" + relative, &info) == 0 else { continue }
            if info.st_dev != top.st_dev {
                return "Another disk is mounted inside (\(relative)). Eject it first."
            }
            if mode == .secureErase {
                if info.st_flags & DirectoryReader.datalessFlag != 0 {
                    return "Some files inside are stored in iCloud only (\(relative))."
                }
                if info.st_mode & S_IFMT == S_IFREG && info.st_nlink > 1 {
                    return "A file inside has other names (hard links): \(relative). Use Delete Permanently."
                }
            }
        }
        return nil
    }

    /// Overwrites every regular file under `path` with random data, flushes it to the drive,
    /// then deletes everything. Symlinks are removed, never followed.
    static func secureErase(_ path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw Failure.failed(path, "it no longer exists.") }
        if info.st_flags & DirectoryReader.datalessFlag != 0 {
            throw Failure.failed(path, "it is stored in iCloud, not on this Mac. Delete it from iCloud instead.")
        }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for entry in entries { try secureErase(path + "/" + entry) }
            guard rmdir(path) == 0 else { throw Failure.failed(path, String(cString: strerror(errno))) }
        case S_IFREG:
            if info.st_nlink > 1 {
                throw Failure.failed(path, "it has other names (hard links), so its content would survive. Use Delete Permanently.")
            }
            try overwrite(path, size: info.st_size)
            guard unlink(path) == 0 else { throw Failure.failed(path, String(cString: strerror(errno))) }
        default:
            guard unlink(path) == 0 else { throw Failure.failed(path, String(cString: strerror(errno))) }
        }
    }

    private static func overwrite(_ path: String, size: off_t) throws {
        let fd = open(path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.failed(path, String(cString: strerror(errno))) }
        defer { close(fd) }
        // Bypass the cache so the random bytes reach the drive.
        _ = fcntl(fd, F_NOCACHE, 1)
        let chunk = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var written: off_t = 0
        while written < size {
            let count = Int(min(off_t(chunk), size - written))
            arc4random_buf(buffer, count)
            let result = pwrite(fd, buffer, count, written)
            if result < 0 {
                if errno == EINTR { continue }
                throw Failure.failed(path, String(cString: strerror(errno)))
            }
            written += off_t(result)
        }
        guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else {
            throw Failure.failed(path, "the drive did not confirm the overwrite.")
        }
    }
}

/// Facts about what may still hold a copy after a secure erase.
public struct EraseEnvironment: Sendable {
    public var fileVaultOn: Bool?
    public var localSnapshots: Int?
    public var timeMachineConfigured: Bool?

    public init(fileVaultOn: Bool? = nil, localSnapshots: Int? = nil, timeMachineConfigured: Bool? = nil) {
        self.fileVaultOn = fileVaultOn
        self.localSnapshots = localSnapshots
        self.timeMachineConfigured = timeMachineConfigured
    }

    /// Reads them with system tools that work without admin rights.
    public static func current() -> EraseEnvironment {
        var environment = EraseEnvironment()
        if let output = run("/usr/bin/fdesetup", ["status"]) {
            environment.fileVaultOn = output.contains("FileVault is On")
        }
        if let output = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) {
            environment.localSnapshots = output.split(separator: "\n").filter { $0.contains("com.apple") }.count
        }
        if let output = run("/usr/bin/tmutil", ["destinationinfo"]) {
            environment.timeMachineConfigured = output.contains("Name")
        }
        return environment
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
