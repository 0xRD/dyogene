import Darwin
import Foundation

/// One entry of a directory, as `getattrlistbulk` returns it. Metadata only: Dyogène never opens
/// a file to read it.
struct RawEntry: Sendable {
    enum ObjectType: Sendable { case file, directory, symlink, other }

    var name: String
    var type: ObjectType
    var device: Int32
    var modified: Double
    var accessed: Double
    var flags: UInt32
    var fileID: UInt64
    var linkCount: UInt32
    var allocatedSize: UInt64
}

/// Reads whole directories with `getattrlistbulk(2)`: one system call returns the names, types,
/// dates and sizes of many entries at once, far faster than a `stat` per file.
enum DirectoryReader {
    // Attribute bits from <sys/attr.h>, spelled out because Swift imports some as Int32.
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnDevID: UInt32 = 0x0000_0002
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let cmnAccTime: UInt32 = 0x0000_1000
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004

    /// `SF_DATALESS`: an iCloud or File Provider placeholder.
    static let datalessFlag: UInt32 = 0x4000_0000

    enum Failure: Error { case cannotOpen(Int32) }

    static func read(_ path: String) throws -> [RawEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.cannotOpen(errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = cmnReturnedAttrs | cmnName | cmnDevID | cmnObjType | cmnModTime
            | cmnAccTime | cmnFlags | cmnFileID | cmnError
        request.fileattr = fileLinkCount | fileAllocSize

        let bufferSize = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [RawEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 {
                if errno == EINTR { continue }
                // Entries read so far are still worth keeping.
                if entries.isEmpty { throw Failure.cannotOpen(errno) }
                break
            }
            if count == 0 { break }
            var cursor = buffer
            for _ in 0..<count {
                let length = Int(cursor.loadUnaligned(as: UInt32.self))
                if let entry = parse(cursor) { entries.append(entry) }
                cursor += length
            }
        }
        return entries
    }

    private static func parse(_ start: UnsafeMutableRawPointer) -> RawEntry? {
        var p = start + 4
        let returnedCommon = p.loadUnaligned(as: UInt32.self)
        let returnedFile = p.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
        p += 20 // attribute_set_t: common, vol, dir, file, fork

        var name = ""
        var device: Int32 = 0
        var objectType: UInt32 = 0
        var modified = 0.0
        var accessed = 0.0
        var flags: UInt32 = 0
        var fileID: UInt64 = 0

        if returnedCommon & cmnName != 0 {
            let offset = Int(p.loadUnaligned(as: Int32.self))
            let length = Int(p.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let bytes = UnsafeRawBufferPointer(start: p + offset, count: max(0, length - 1))
            name = String(decoding: bytes, as: UTF8.self)
            p += 8
        }
        if returnedCommon & cmnDevID != 0 { device = p.loadUnaligned(as: Int32.self); p += 4 }
        if returnedCommon & cmnObjType != 0 { objectType = p.loadUnaligned(as: UInt32.self); p += 4 }
        if returnedCommon & cmnModTime != 0 { modified = time(p); p += 16 }
        if returnedCommon & cmnAccTime != 0 { accessed = time(p); p += 16 }
        if returnedCommon & cmnFlags != 0 { flags = p.loadUnaligned(as: UInt32.self); p += 4 }
        if returnedCommon & cmnFileID != 0 { fileID = p.loadUnaligned(as: UInt64.self); p += 8 }
        if returnedCommon & cmnError != 0 {
            let error = p.loadUnaligned(as: UInt32.self)
            p += 4
            if error != 0 { return nil }
        }

        var linkCount: UInt32 = 1
        var allocated: UInt64 = 0
        if returnedFile & fileLinkCount != 0 { linkCount = p.loadUnaligned(as: UInt32.self); p += 4 }
        if returnedFile & fileAllocSize != 0 { allocated = UInt64(max(0, p.loadUnaligned(as: Int64.self))); p += 8 }

        guard !name.isEmpty else { return nil }
        let type: RawEntry.ObjectType = switch objectType {
        case 1: .file       // VREG
        case 2: .directory  // VDIR
        case 5: .symlink    // VLNK
        default: .other
        }
        return RawEntry(name: name, type: type, device: device, modified: modified, accessed: accessed,
                        flags: flags, fileID: fileID, linkCount: linkCount, allocatedSize: allocated)
    }

    private static func time(_ p: UnsafeMutableRawPointer) -> Double {
        let seconds = p.loadUnaligned(as: Int64.self)
        let nanoseconds = p.loadUnaligned(fromByteOffset: 8, as: Int64.self)
        return Double(seconds) + Double(nanoseconds) / 1e9
    }

    /// Device of a path, to avoid crossing into other volumes.
    static func device(of path: String) -> Int32? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_dev
    }
}
