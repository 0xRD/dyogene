import AppKit
import DyogeneCore
import Observation
import SwiftUI
import Synchronization

/// Everything the window shows. One per app (Dyogène has one main window).
@MainActor @Observable
final class AppModel {
    enum Screen: String, CaseIterable, Identifiable {
        case map, hoard, suspects
        var id: String { rawValue }
        var title: String {
            switch self {
            case .map: "Map"
            case .hoard: "Hoard"
            case .suspects: "Suspects"
            }
        }
        var symbol: String {
            switch self {
            case .map: "square.grid.3x3.square"
            case .hoard: "archivebox"
            case .suspects: "magnifyingglass"
            }
        }
    }

    enum Lens: String, CaseIterable, Identifiable {
        case dust, kind, plain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dust: "Dust"
            case .kind: "Kind"
            case .plain: "Plain"
            }
        }
        var help: String {
            switch self {
            case .dust: "Colour by time since last use: teal is fresh, sand is forgotten."
            case .kind: "Colour by kind of content: videos, apps, developer files..."
            case .plain: "No colour coding, just sizes."
            }
        }
    }

    enum Phase: Equatable {
        case welcome
        case scanning
        case ready
        case failed(String)
    }

    struct Hover: Equatable {
        /// Node under the cursor, or nil for an "N smaller items" tile.
        var node: Int?
        var parent: Int
        var groupCount: Int
        var groupSize: UInt64
        /// Cursor position in the map's coordinates.
        var location: CGPoint
        var mapSize: CGSize
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var undo: [FileRemover.Outcome] = []
        var isError = false
    }

    // MARK: State

    var screen: Screen = .map
    var lens: Lens = .dust { didSet { UserDefaults.standard.set(lens.rawValue, forKey: "lens") } }
    var phase: Phase = .welcome
    private(set) var tree: FileTree?
    /// Bumped whenever the tree changes, so the map lays itself out again.
    private(set) var treeVersion = 0
    private(set) var volume: VolumeUsage?
    private(set) var home = NSHomeDirectory()
    var focus = FileTree.root
    var selection: Int?
    var hover: Hover?
    private(set) var now = Date().timeIntervalSince1970

    // Scan progress, refreshed a few times a second while scanning.
    private(set) var scannedFiles: UInt64 = 0
    private(set) var scannedBytes: UInt64 = 0
    private(set) var settled: [SettledItem] = []
    private(set) var scanStarted = Date()
    private(set) var scanDuration: TimeInterval = 0
    private var scanTask: Task<Void, Never>?

    var fullDiskAccess = FullDiskAccess.isGranted
    var scanRoot: String { didSet { UserDefaults.standard.set(scanRoot, forKey: "scanRoot") } }
    var exclusions: [String] { didSet { UserDefaults.standard.set(exclusions, forKey: "exclusions") } }
    let isDemo: Bool

    var hoardFilter = Hoard.Filter()
    var removal: RemovalRequest?
    var toast: Toast?
    var navigationHistory: [Int] = []

    /// Spotlight dates, fetched lazily for what is on screen.
    private var spotlight: [Int: (date: Double, source: LastUsed.Source)] = [:]
    private var findingsCache: (version: Int, value: [SuspectFinding])?

    init() {
        let environment = ProcessInfo.processInfo.environment
        isDemo = environment["DYOGENE_DEMO"] == "1"
        scanRoot = UserDefaults.standard.string(forKey: "scanRoot") ?? NSHomeDirectory()
        exclusions = UserDefaults.standard.stringArray(forKey: "exclusions") ?? []
        if let saved = UserDefaults.standard.string(forKey: "lens").flatMap(Lens.init) { lens = saved }
        if isDemo { loadDemo() }
        if let screen = environment["DYOGENE_SCREEN"].flatMap(Screen.init) { self.screen = screen }
    }

    // MARK: Scanning

    var isScanning: Bool { phase == .scanning }

    func loadDemo() {
        now = Date().timeIntervalSince1970
        let demo = DemoTree.make(now: now)
        home = DemoTree.home
        install(demo, volume: DemoTree.volume(for: demo))
        if let path = ProcessInfo.processInfo.environment["DYOGENE_SELECT"],
           let index = demo.index(ofPath: DemoTree.home + "/" + path) {
            selection = index
            if let parent = demo.parent(of: index), ProcessInfo.processInfo.environment["DYOGENE_FOCUS_PARENT"] == "1" {
                focus = parent
            }
        }
    }

    func scan(_ root: String? = nil) {
        if let root { scanRoot = root }
        if isDemo {
            loadDemo()
            return
        }
        scanTask?.cancel()
        fullDiskAccess = FullDiskAccess.isGranted
        let options = ScanOptions(root: scanRoot, exclusions: exclusions)
        let progress = ScanProgress()
        let scanner = Scanner(options: options, progress: progress)
        phase = .scanning
        hover = nil
        selection = nil
        settled = []
        scannedFiles = 0
        scannedBytes = 0
        scanStarted = Date()
        home = NSHomeDirectory()
        let root = scanRoot

        scanTask = Task { [weak self] in
            let done = ScanDone()
            let work = Task.detached(priority: .userInitiated) {
                defer { done.flag.store(true, ordering: .releasing) }
                return try await scanner.scan()
            }
            // Poll the counters while the scan runs: no timer outlives the scan.
            while !Task.isCancelled {
                guard let self else { work.cancel(); return }
                self.scannedFiles = progress.fileCount
                self.scannedBytes = progress.byteCount
                let settledNow = progress.settled
                if settledNow.count != self.settled.count { self.settled = settledNow }
                if (try? await Task.sleep(for: .milliseconds(120))) == nil { break }
                if done.flag.load(ordering: .acquiring) { break }
            }
            if Task.isCancelled {
                work.cancel()
                return
            }
            do {
                let tree = try await work.value
                guard let self else { return }
                self.now = Date().timeIntervalSince1970
                self.scanDuration = Date().timeIntervalSince(self.scanStarted)
                self.install(tree, volume: VolumeUsage.of(root))
            } catch {
                self?.phase = .failed("\(error)")
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = tree == nil ? .welcome : .ready
    }

    private func install(_ tree: FileTree, volume: VolumeUsage?) {
        self.tree = tree
        self.volume = volume
        treeVersion += 1
        focus = FileTree.root
        selection = nil
        navigationHistory = []
        spotlight = [:]
        findingsCache = nil
        phase = .ready
    }

    // MARK: Navigation

    /// The node the inspector describes: the selection, or the focused folder.
    var inspected: Int { selection ?? focus }

    func select(_ index: Int?) {
        selection = index
    }

    /// Zooms into a folder; for a file or group, into the folder that holds it.
    func zoom(into index: Int) {
        guard let tree else { return }
        var target = index
        if !tree[target].isDirectory || tree[target].flags.contains(.smallGroup) {
            guard let parent = tree.parent(of: target) else { return }
            target = parent
        }
        guard target != focus, !tree.visibleChildren(of: target).isEmpty else { return }
        focus = target
        hover = nil
        if selection.map({ !tree.isAncestor(target, of: $0) }) ?? false { selection = nil }
    }

    func zoomOut() {
        guard let tree, let parent = tree.parent(of: focus) else { return }
        let previous = focus
        focus = parent
        hover = nil
        selection = previous
    }

    /// Shows a node on the map: focuses its folder and selects it.
    func showOnMap(_ index: Int) {
        guard let tree else { return }
        screen = .map
        if let parent = tree.parent(of: index) { focus = parent }
        selection = index
    }

    // MARK: Data for the screens

    func lastUsed(_ index: Int) -> (date: Double, source: LastUsed.Source) {
        guard let tree else { return (0, .fileSystem) }
        if let cached = spotlight[index] { return cached }
        let node = tree[index]
        guard node.isActionable, isDemo == false else { return (node.lastUsed, .fileSystem) }
        let best = LastUsed.best(path: tree.path(of: index), scanned: node.lastUsed)
        spotlight[index] = best
        return best
    }

    var findings: [SuspectFinding] {
        guard let tree else { return [] }
        if let cache = findingsCache, cache.version == treeVersion { return cache.value }
        let value = Suspects.findings(in: tree, home: home, now: now)
        findingsCache = (treeVersion, value)
        return value
    }

    var hoardItems: [Int] {
        guard let tree else { return [] }
        return Hoard.items(in: tree, filter: hoardFilter, now: now)
    }

    func path(_ index: Int) -> String { tree?.path(of: index) ?? "" }

    // MARK: Actions

    func reveal(_ index: Int) {
        guard let tree, !isDemo else { return }
        let path = tree.path(of: index)
        if tree[index].flags.contains(.smallGroup) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func open(_ index: Int) {
        guard let tree, !isDemo else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: tree.path(of: index)))
    }

    func quickLook(_ index: Int) {
        guard let tree, !isDemo, tree[index].isActionable else { return }
        QuickLook.shared.show(URL(fileURLWithPath: tree.path(of: index)))
    }

    func copyPath(_ index: Int) {
        guard let tree else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tree.path(of: index), forType: .string)
        toast = Toast(message: "Path copied.")
    }

    func requestRemoval(_ indices: [Int], mode: RemovalMode) {
        guard let tree else { return }
        let items = indices.filter { tree[$0].isActionable && $0 != FileTree.root }
        guard !items.isEmpty else { return }
        removal = RemovalRequest(tree: tree, indices: items, mode: mode, home: home, demo: isDemo)
    }

    func performRemoval() {
        guard let request = removal, var tree else { return }
        removal = nil
        let targets = request.items.filter(\.allowed)
        if isDemo {
            for item in targets { tree.markRemoved(item.index) }
            self.tree = tree
            treeVersion += 1
            toast = Toast(message: "Demo: nothing was removed.")
            return
        }
        let mode = request.mode
        let home = self.home
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                targets.map { item in
                    Result { try FileRemover.remove(item.path, mode: mode, home: home) }
                        .mapError { $0 as? FileRemover.Failure ?? .failed(item.path, "\($0)") }
                }
            }.value
            var outcomes: [FileRemover.Outcome] = []
            var errors: [String] = []
            guard var current = self.tree else { return }
            for (item, result) in zip(targets, results) {
                switch result {
                case .success(let outcome):
                    outcomes.append(outcome)
                    current.markRemoved(item.index)
                case .failure(let error):
                    errors.append(error.description)
                }
            }
            self.tree = current
            self.treeVersion += 1
            if let selection = self.selection, current[selection].flags.contains(.removed) { self.selection = nil }
            self.volume = VolumeUsage.of(current.rootPath)
            if !errors.isEmpty {
                self.toast = Toast(message: errors.joined(separator: "\n"), isError: true)
            } else {
                let size = Format.bytes(targets.reduce(0) { $0 + $1.size })
                let verb = switch mode {
                case .trash: "Moved to the Trash"
                case .permanent: "Deleted"
                case .secureErase: "Erased"
                }
                let what = targets.count == 1 ? targets[0].name : "\(targets.count) items"
                self.toast = Toast(message: "\(verb): \(what), \(size).", undo: mode == .trash ? outcomes : [])
            }
        }
    }

    /// Puts back what the last "Move to Trash" moved. The map shows it again after a rescan.
    func putBack(_ outcomes: [FileRemover.Outcome]) {
        var errors: [String] = []
        for outcome in outcomes {
            do { try FileRemover.putBack(outcome) } catch { errors.append("\(error)") }
        }
        toast = errors.isEmpty
            ? Toast(message: "Put back. Rescan to see it on the map again.")
            : Toast(message: errors.joined(separator: "\n"), isError: true)
    }
}

final class ScanDone: Sendable {
    let flag = Atomic<Bool>(false)
}

/// What a removal sheet shows and confirms.
@MainActor @Observable
final class RemovalRequest: Identifiable {
    struct Item: Identifiable {
        let index: Int
        let path: String
        let name: String
        let size: UInt64
        let refusal: String?
        let warnings: [String]
        var id: Int { index }
        var allowed: Bool { refusal == nil }
    }

    let id = UUID()
    let mode: RemovalMode
    let items: [Item]
    let isDemo: Bool
    /// The "I understand" checkbox of permanent removals.
    var acknowledged = false
    var environment: EraseEnvironment?
    let hold = HoldState()

    init(tree: FileTree, indices: [Int], mode: RemovalMode, home: String, demo: Bool) {
        self.mode = mode
        self.isDemo = demo
        items = indices.map { index in
            let path = tree.path(of: index)
            let node = tree[index]
            var refusal: String?
            if case .refused(let reason) = RemovalPolicy.verdict(for: path, home: home) { refusal = reason }
            if mode == .secureErase, node.flags.contains(.inCloud) {
                refusal = "Stored in iCloud, not on this Mac."
            }
            return Item(index: index, path: path, name: node.name, size: node.size, refusal: refusal,
                        warnings: RemovalPolicy.warnings(for: path, home: home, isInCloud: node.flags.contains(.inCloud)))
        }
        if mode == .secureErase && demo {
            // Fixed facts: demo screenshots must not show this Mac's state.
            environment = EraseEnvironment(fileVaultOn: true, localSnapshots: 0, timeMachineConfigured: true)
        } else if mode == .secureErase {
            Task { [weak self] in
                let environment = await Task.detached { EraseEnvironment.current() }.value
                self?.environment = environment
            }
        }
    }

    var allowedItems: [Item] { items.filter(\.allowed) }
    var totalSize: UInt64 { allowedItems.reduce(0) { $0 + $1.size } }
    var needsAcknowledgement: Bool { mode != .trash }
    var canConfirm: Bool { !allowedItems.isEmpty && (!needsAcknowledgement || acknowledged) }
}

/// Progress of a press-and-hold button.
@MainActor @Observable
final class HoldState {
    var pressStarted: Date?
    var fired = false
}
