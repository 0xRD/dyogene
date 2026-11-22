import AppKit
import DyogeneCore
import SwiftUI

@main
struct DyogeneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel()

    var body: some Scene {
        Window("Dyogène", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(AppDelegate.forcedScheme)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Again") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isScanning)
                Button("Scan Home Folder") { model.scan(NSHomeDirectory()) }
                Button("Scan Whole Mac") { model.scan(ScanLocation.wholeMac) }
                Button("Choose Folder to Scan…") { ScanLocation.choose(model) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Map") {
                Picker("Lens", selection: Binding(get: { model.lens }, set: { model.lens = $0 })) {
                    ForEach(AppModel.Lens.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Back to Top") { model.focus = FileTree.root }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// DYOGENE_APPEARANCE=light|dark, for screenshots.
    static let forcedScheme: ColorScheme? = switch ProcessInfo.processInfo.environment["DYOGENE_APPEARANCE"] {
    case "light": .light
    case "dark": .dark
    default: nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let image = NSImage(named: "Dyogene") ?? Bundle.main.image(forResource: "Dyogene") {
            NSApp.applicationIconImage = image
        }
        NSApp.activate()
        DebugSnapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum ScanLocation {
    /// The data volume holds everything that is not macOS itself (apps, users, Library).
    static let wholeMac = "/System/Volumes/Data"

    static func title(for path: String) -> String {
        if path == NSHomeDirectory() { return "Home Folder" }
        if path == wholeMac || path == "/" { return "Whole Mac" }
        return FileManager.default.displayName(atPath: path)
    }

    @MainActor static func choose(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan. Dyogène reads names, sizes and dates only."
        if panel.runModal() == .OK, let url = panel.url { model.scan(url.path) }
    }
}
