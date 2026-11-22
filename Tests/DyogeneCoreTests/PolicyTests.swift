import Testing
@testable import DyogeneCore

@Suite struct PolicyTests {
    let home = "/Users/alice"

    @Test(arguments: ["/", "/System", "/System/Library/CoreServices", "/usr/bin/ls", "/bin", "/private/var/db",
                      "/Users/alice", "/Users/alice/Library", "/Users/alice/Documents", "/Users/alice/Library/Caches",
                      "/Applications", "/Library", "/Users/bob/Movies/x.mov", "/Volumes/Backup", "/System/Volumes/Data",
                      "/System/Volumes/Data/Users/alice", "/System/Volumes/Data/private/var/db", "/Applications/Safari.app",
                      "/var/log", "/tmp/x", "relative/path", "/Users/alice/Library/Mobile Documents"])
    func refuses(_ path: String) {
        #expect(RemovalPolicy.verdict(for: path, home: home) != .allowed)
    }

    @Test(arguments: ["/Users/alice/Movies/holiday.mov", "/Users/alice/Library/Caches/com.example",
                      "/Users/alice/Downloads/setup.dmg", "/Applications/Example.app", "/usr/local/Cellar/thing",
                      "/System/Volumes/Data/Users/alice/Downloads/big.zip", "/Volumes/Backup/old", "/Users/alice/.Trash/x"])
    func allows(_ path: String) {
        #expect(RemovalPolicy.verdict(for: path, home: home) == .allowed)
    }

    @Test func dotDotCannotEscape() {
        #expect(RemovalPolicy.verdict(for: "/Users/alice/Movies/../../../System", home: home) != .allowed)
        #expect(RemovalPolicy.verdict(for: "/Users/alice/Movies/..", home: home) != .allowed)
    }

    @Test func cloudWarning() {
        let notes = RemovalPolicy.warnings(for: "/Users/alice/Library/Mobile Documents/com~apple~CloudDocs/a.pdf", home: home, isInCloud: false)
        #expect(notes.contains { $0.contains("cloud") })
    }
}
