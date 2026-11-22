import AppKit
import DyogeneCore
import Foundation

// `dyogene`: metadata-only reports for the Claude skill and for scripts. It reads names, sizes and
// dates, never file contents, and it has no command that deletes or moves anything.

let usage = """
dyogene: see what takes space on your Mac (metadata only, nothing is ever read or deleted).

Usage:
  dyogene report   [--path DIR]                  Everything in one scan: summary, largest items, unused items, suspects
  dyogene summary  [--path DIR]                  Disk use, coverage, share by kind and by age, largest folders
  dyogene top      [--path DIR] [--limit N] [--folders]
                                                 Largest files and packages (or folders of files)
  dyogene stale    [--path DIR] [--older-than 1y] [--min-size 100MB] [--limit N]
                                                 Large items nobody used for a while
  dyogene suspects [--path DIR]                  Usual reclaimable places (caches, build data, installers...)
  dyogene tree     DIR [--depth 2]               Folder breakdown, largest first
  dyogene reveal   PATH                          Select PATH in Finder

Options:
  --path DIR       Folder to scan (default: your home folder)
  --exclude DIR    Folder to skip (repeatable)
  --demo           Use the built-in demo data instead of scanning
  --text           Plain text instead of JSON (top, stale, tree)

All output is JSON unless --text is given. Paths can be personal: handle them with care.
"""

struct Arguments {
    var command = ""
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []
    var exclusions: [String] = []

    init(_ raw: [String]) {
        var iterator = raw.makeIterator()
        let valued: Set<String> = ["--path", "--limit", "--older-than", "--min-size", "--depth", "--exclude"]
        while let argument = iterator.next() {
            if valued.contains(argument) {
                let value = iterator.next() ?? ""
                if argument == "--exclude" { exclusions.append(expand(value)) } else { options[argument] = value }
            } else if argument.hasPrefix("--") {
                flags.insert(argument)
            } else if command.isEmpty {
                command = argument
            } else {
                positional.append(argument)
            }
        }
    }

    func int(_ name: String, default value: Int) -> Int { options[name].flatMap(Int.init) ?? value }
}

func expand(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") { return (expanded as NSString).standardizingPath }
    return ((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded) as NSString).standardizingPath
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("dyogene: \(message)\n".utf8))
    exit(1)
}

func loadTree(_ arguments: Arguments, path: String? = nil) async -> (tree: FileTree, home: String, volume: VolumeUsage?) {
    if arguments.flags.contains("--demo") {
        let tree = DemoTree.make()
        return (tree, DemoTree.home, DemoTree.volume(for: tree))
    }
    let root = path ?? arguments.options["--path"].map(expand) ?? NSHomeDirectory()
    let scanner = Scanner(options: ScanOptions(root: root, exclusions: arguments.exclusions))
    do {
        let tree = try await scanner.scan()
        return (tree, NSHomeDirectory(), VolumeUsage.of(root))
    } catch {
        fail("\(error)")
    }
}

func printText(_ entries: [Report.Entry]) {
    for entry in entries {
        let size = entry.sizeText.padding(toLength: 10, withPad: " ", startingAt: 0)
        let age = entry.lastUsedAge.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("\(size)  \(age)  \(entry.path)")
    }
}

func printTree(_ entry: Report.Entry, indent: String = "") {
    print("\(indent)\(entry.sizeText.padding(toLength: 10, withPad: " ", startingAt: 0))  \(entry.name)  (\(entry.lastUsedAge))")
    for child in entry.children ?? [] { printTree(child, indent: indent + "  ") }
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
let now = Date().timeIntervalSince1970
let text = arguments.flags.contains("--text")

switch arguments.command {
case "report":
    let (tree, home, volume) = await loadTree(arguments)
    print(Report.json(Report.full(tree: tree, volume: volume, fullDiskAccess: FullDiskAccess.isGranted, home: home, now: now)))

case "summary":
    let (tree, _, volume) = await loadTree(arguments)
    print(Report.json(Report.summary(of: tree, volume: volume, fullDiskAccess: FullDiskAccess.isGranted, now: now)))

case "top":
    let (tree, _, _) = await loadTree(arguments)
    let mode: Hoard.Mode = arguments.flags.contains("--folders") ? .folders : .items
    let entries = Hoard.items(in: tree, filter: .init(mode: mode, limit: arguments.int("--limit", default: 30)), now: now)
        .map { Report.entry($0, in: tree, now: now) }
    if text { printText(entries) } else { print(Report.json(entries)) }

case "stale":
    let (tree, _, _) = await loadTree(arguments)
    guard let age = Format.parseAge(arguments.options["--older-than"] ?? "1y") else { fail("--older-than takes values like 6m, 1y, 90d.") }
    guard let minimum = Format.parseBytes(arguments.options["--min-size"] ?? "100MB") else { fail("--min-size takes values like 500MB, 2GB.") }
    let filter = Hoard.Filter(mode: .items, unusedFor: age, minimumSize: minimum, limit: arguments.int("--limit", default: 30))
    let entries = Hoard.items(in: tree, filter: filter, now: now).map { Report.entry($0, in: tree, now: now) }
    if text { printText(entries) } else { print(Report.json(entries)) }

case "suspects":
    let (tree, home, _) = await loadTree(arguments)
    print(Report.json(Report.suspects(in: tree, home: home, now: now)))

case "tree":
    guard let target = arguments.positional.first.map(expand) ?? arguments.options["--path"].map(expand) else {
        fail("tree needs a folder.")
    }
    let (tree, _, _) = await loadTree(arguments, path: arguments.flags.contains("--demo") ? nil : target)
    let start = arguments.flags.contains("--demo") ? (tree.index(ofPath: target) ?? FileTree.root) : FileTree.root
    let entry = Report.entry(start, in: tree, now: now, depth: max(1, arguments.int("--depth", default: 2)))
    if text { printTree(entry) } else { print(Report.json(entry)) }

case "reveal":
    guard let target = arguments.positional.first.map(expand) else { fail("reveal needs a path.") }
    guard FileManager.default.fileExists(atPath: target) else { fail("\(target) does not exist.") }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    print(Report.json(["revealed": target]))

case "", "help", "--help", "-h":
    print(usage)

default:
    fail("unknown command '\(arguments.command)'. Run dyogene help.")
}
