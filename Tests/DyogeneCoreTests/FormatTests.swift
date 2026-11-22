import Testing
@testable import DyogeneCore

@Suite struct FormatTests {
    @Test func bytes() {
        #expect(Format.bytes(0) == "0 bytes")
        #expect(Format.bytes(1) == "1 byte")
        #expect(Format.bytes(1_500) == "1.5 KB")
        #expect(Format.bytes(38_000_000_000) == "38 GB")
        #expect(Format.bytes(2_400_000) == "2.4 MB")
    }

    @Test func parsing() {
        #expect(Format.parseBytes("500MB") == 500_000_000)
        #expect(Format.parseBytes("1.5 gb") == 1_500_000_000)
        #expect(Format.parseBytes("abc") == nil)
        #expect(Format.parseAge("1y") == 365 * Dust.day)
        #expect(Format.parseAge("6m") == 180 * Dust.day)
        #expect(Format.parseAge("x") == nil)
    }

    @Test func ages() {
        let now = 1_800_000_000.0
        #expect(Format.age(lastUsed: 0, now: now) == "unknown")
        #expect(Format.age(lastUsed: now - 10, now: now) == "today")
        #expect(Format.age(lastUsed: now - 400 * Dust.day, now: now) == "1 year ago")
        #expect(Format.age(lastUsed: now - 65 * Dust.day, now: now) == "2 months ago")
    }

    @Test func dustIsMonotonicAndBounded() {
        let now = 1_800_000_000.0
        var previous = -1.0
        for days in [0.0, 1, 7, 30, 182, 365, 1000, 5000] {
            let level = Dust.level(lastUsed: now - days * Dust.day, now: now)
            #expect(level >= previous && level <= 1)
            previous = level
        }
        #expect(Dust.level(lastUsed: 0, now: now) == 0)
        #expect(Dust.level(lastUsed: now - 4000 * Dust.day, now: now) == 1)
        #expect(abs(Dust.age(forLevel: Dust.level(lastUsed: now - 100 * Dust.day, now: now)) - 100 * Dust.day) < 60)
    }

    @Test func kinds() {
        #expect(KindClassifier.kind(ofFile: "Clip.MOV") == .video)
        #expect(KindClassifier.kind(ofFile: "setup.dmg") == .archive)
        #expect(KindClassifier.kind(ofFile: "Docker.raw") == .virtualDisk)
        #expect(KindClassifier.kind(ofFile: "README") == .other)
        #expect(KindClassifier.isPackage(directoryName: "Safari.app"))
        #expect(!KindClassifier.isPackage(directoryName: "Movies"))
        #expect(KindClassifier.kind(ofDirectory: "node_modules", parentName: "site") == .developer)
        #expect(KindClassifier.kind(ofDirectory: "Caches", parentName: "Library") == .cache)
        #expect(KindClassifier.kind(ofDirectory: "Photos Library.photoslibrary", parentName: nil) == .photo)
    }
}
