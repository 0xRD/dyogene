import Foundation

/// A made-up home folder with generic names, for screenshots and demos. Never real data.
public enum DemoTree {
    public static let home = "/Users/demo"

    public static func make(now: Double = Date().timeIntervalSince1970) -> FileTree {
        var random = SeededRandom(seed: 7)
        let day = Dust.day
        func ago(_ days: Double) -> Double { now - days * day }
        let gb: UInt64 = 1_000_000_000
        let mb: UInt64 = 1_000_000

        func file(_ name: String, _ size: UInt64, _ days: Double) -> DemoItem {
            .file(name, size, ago(days))
        }
        func folder(_ name: String, _ items: [DemoItem]) -> DemoItem { .folder(name, items) }
        func many(_ prefix: String, _ ext: String, count: Int, size: ClosedRange<UInt64>, days: ClosedRange<Double>) -> [DemoItem] {
            (1...count).map { i in
                .file("\(prefix) \(i).\(ext)", random.next(in: size), ago(random.next(in: days)))
            }
        }

        let tree: DemoItem = folder("demo", [
            folder("Movies", [
                folder("Holiday footage 2021", many("Clip", "mov", count: 14, size: 2 * gb...9 * gb, days: 1000...1100)),
                folder("Screen recordings", many("Screen Recording", "mov", count: 22, size: 200 * mb...1_400 * mb, days: 20...400)),
                file("Wedding film master.mp4", 38 * gb, 1400),
                file("Interview raw.braw", 21 * gb, 820),
                folder("Edit.fcpbundle", many("Render", "mov", count: 6, size: 1 * gb...4 * gb, days: 600...700)),
            ]),
            folder("Library", [
                folder("Caches", [
                    folder("com.example.browser", many("cache", "db", count: 30, size: 20 * mb...300 * mb, days: 0...3)),
                    folder("Homebrew", many("bottle", "tar.gz", count: 25, size: 10 * mb...250 * mb, days: 30...300)),
                    folder("com.example.music", many("chunk", "dat", count: 12, size: 50 * mb...400 * mb, days: 2...40)),
                ]),
                folder("Developer", [
                    folder("Xcode", [
                        folder("DerivedData", [
                            folder("Atlas-abcdef", many("Build", "o", count: 20, size: 100 * mb...900 * mb, days: 5...60)),
                            folder("Lumen-ghijkl", many("Build", "o", count: 16, size: 100 * mb...700 * mb, days: 200...400)),
                        ]),
                        folder("iOS DeviceSupport", [
                            folder("17.4 (21E219)", many("Symbols", "dylib", count: 6, size: 400 * mb...900 * mb, days: 500...520)),
                            folder("18.1 (22B83)", many("Symbols", "dylib", count: 6, size: 400 * mb...900 * mb, days: 200...220)),
                        ]),
                        folder("Archives", many("Atlas", "xcarchive", count: 5, size: 300 * mb...800 * mb, days: 100...600)),
                    ]),
                    folder("CoreSimulator", [
                        folder("Devices", many("Simulator", "img", count: 9, size: 1 * gb...4 * gb, days: 60...500)),
                    ]),
                ]),
                folder("Application Support", [
                    folder("MobileSync", [folder("Backup", [
                        folder("Old phone", many("backup", "db", count: 8, size: 2 * gb...5 * gb, days: 900...950)),
                    ])]),
                    folder("Messages app", many("attachment", "heic", count: 40, size: 5 * mb...60 * mb, days: 1...300)),
                ]),
                folder("Containers", [
                    folder("com.docker.docker", [folder("Data", [folder("vms", [folder("0", [
                        file("Docker.raw", 46 * gb, 12),
                    ])])])]),
                ]),
            ]),
            folder("Downloads", [
                file("Design tool installer.dmg", 1_900 * mb, 400),
                file("Operating system image.iso", 6_200 * mb, 700),
                file("Game assets.zip", 4_300 * mb, 260),
                file("Printer driver.pkg", 480 * mb, 900),
                file("Dataset export.csv", 2_400 * mb, 220),
                folder("Old project files", many("Draft", "psd", count: 18, size: 80 * mb...600 * mb, days: 600...900)),
                file("Lecture recording.mp4", 3_100 * mb, 15),
            ]),
            folder("Pictures", [
                folder("Photos Library.photoslibrary", many("Masters", "heic", count: 40, size: 500 * mb...2 * gb, days: 0...30)),
                folder("Scans", many("Scan", "tiff", count: 30, size: 30 * mb...120 * mb, days: 300...1200)),
            ]),
            folder("Music", [
                folder("Music library.musiclibrary", many("Album", "m4a", count: 30, size: 100 * mb...400 * mb, days: 5...200)),
                folder("Stems", many("Stem", "wav", count: 20, size: 200 * mb...700 * mb, days: 800...1200)),
            ]),
            folder("Documents", [
                folder("Invoices", many("Invoice", "pdf", count: 60, size: 100_000...900_000, days: 10...700)),
                folder("Thesis", many("Chapter", "pages", count: 8, size: 20 * mb...90 * mb, days: 1100...1300)),
                file("Tax archive.zip", 1_200 * mb, 380),
            ]),
            folder("Projects", [
                folder("website", [
                    folder("node_modules", many("package", "js", count: 40, size: 5 * mb...60 * mb, days: 90...120)),
                    folder("src", many("page", "tsx", count: 40, size: 10_000...200_000, days: 1...30)),
                ]),
                folder("cli-tool", [
                    folder(".build", many("debug", "o", count: 20, size: 40 * mb...200 * mb, days: 30...60)),
                    folder("Sources", many("file", "swift", count: 30, size: 5_000...50_000, days: 1...20)),
                ]),
                folder("Virtual machines", [file("Linux test.utm", 24 * gb, 500)]),
            ]),
            folder(".Trash", many("Deleted", "mov", count: 4, size: 500 * mb...2 * gb, days: 3...10)),
        ])

        guard case .folder = tree else { fatalError("demo root must be a folder") }
        let scanned = build(tree, parentName: nil)
        return TreeBuilder.build(root: scanned, rootPath: home, scannedAt: Date(timeIntervalSince1970: now))
    }

    private static func build(_ item: DemoItem, parentName: String?) -> ScannedFolder {
        guard case .folder(let name, let items) = item else { fatalError("not a folder") }
        var folder = ScannedFolder(name: name, flags: [.directory])
        if KindClassifier.isPackage(directoryName: name) { folder.flags.insert(.package) }
        for child in items {
            switch child {
            case .file(let fileName, let size, let lastUsed):
                folder.files.append(ScannedFile(name: fileName, size: size, lastUsed: lastUsed,
                                                kind: KindClassifier.kind(ofFile: fileName), flags: [], count: 1))
            case .folder:
                folder.folders.append(build(child, parentName: name))
            }
        }
        folder.finish(parentName: parentName)
        return folder
    }

    /// Space use of a made-up 1 TB disk matching the demo tree.
    public static func volume(for tree: FileTree) -> VolumeUsage {
        let total: UInt64 = 994_662_584_320
        let used = tree.totalSize + 58_000_000_000
        return VolumeUsage(name: "Macintosh HD", total: total, free: total - used, freeForImportantUse: total - used + 21_000_000_000)
    }
}

private enum DemoItem {
    case file(String, UInt64, Double)
    case folder(String, [DemoItem])
}

/// Deterministic numbers so demo screenshots do not change between runs.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func nextRaw() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<UInt64>) -> UInt64 {
        range.lowerBound + nextRaw() % (range.upperBound - range.lowerBound + 1)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextRaw() % 1_000_000) / 1_000_000 * (range.upperBound - range.lowerBound)
    }
}
