import DyogeneCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .background(Color.canvas)
                .toolbar { toolbar }
        }
        .sheet(item: $model.removal) { request in
            RemovalSheet(request: request, model: model)
        }
        .overlay(alignment: .bottom) { ToastView(model: model) }
        .onAppear(perform: debugSheet)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have just allowed Full Disk Access in System Settings.
            model.fullDiskAccess = FullDiskAccess.isGranted
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .welcome:
            WelcomeView(model: model)
        case .failed(let message):
            WelcomeView(model: model, error: message)
        case .scanning, .ready:
            switch model.screen {
            case .map: MapScreen(model: model)
            case .hoard: HoardScreen(model: model)
            case .suspects: SuspectsScreen(model: model)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Button("Home Folder") { model.scan(NSHomeDirectory()) }
                Button("Whole Mac") { model.scan(ScanLocation.wholeMac) }
                Divider()
                Button("Choose Folder…") { ScanLocation.choose(model) }
            } label: {
                Label(ScanLocation.title(for: model.scanRoot), systemImage: "externaldrive")
                    .labelStyle(.titleAndIcon)
            }
            .help("Choose what to scan")
            .disabled(model.isScanning)

            if model.isScanning {
                Button("Stop", systemImage: "stop.circle") { model.cancelScan() }
                    .help("Stop scanning")
            } else {
                Button("Scan Again", systemImage: "arrow.clockwise") { model.scan() }
                    .help("Scan again (Cmd+R)")
                    .disabled(model.phase == .welcome)
            }
        }
        if model.screen == .map && model.phase == .ready {
            ToolbarItem(placement: .primaryAction) {
                Picker("Lens", selection: $model.lens) {
                    ForEach(AppModel.Lens.allCases) { lens in
                        Text(lens.title).tag(lens).help(lens.help)
                    }
                }
                .pickerStyle(.segmented)
                .help("How tiles are coloured")
            }
        }
    }

    /// DYOGENE_SHEET=trash|permanent|secure opens a removal sheet on the selection, for screenshots.
    private func debugSheet() {
        guard let name = ProcessInfo.processInfo.environment["DYOGENE_SHEET"], let selection = model.selection else { return }
        let mode: RemovalMode = switch name {
        case "permanent": .permanent
        case "secure": .secureErase
        default: .trash
        }
        model.requestRemoval([selection], mode: mode)
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })) {
            Section {
                ForEach(AppModel.Screen.allCases) { screen in
                    Label(screen.title, systemImage: screen.symbol)
                        .badge(badge(for: screen))
                        .tag(screen)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private func badge(for screen: AppModel.Screen) -> Text? {
        guard model.phase == .ready, screen == .suspects else { return nil }
        let total = model.findings.reduce(0) { $0 + $1.size }
        return total > 0 ? Text(Format.bytes(total)) : nil
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.fullDiskAccess && !model.isDemo {
                Button {
                    NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                } label: {
                    Label("Some folders are hidden", systemImage: "lock")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .help("Without Full Disk Access, folders macOS protects (Mail, Messages, app containers) are skipped. Click to open System Settings.")
            }
            Label("Everything stays on this Mac", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .help("No network access. Dyogène reads names, sizes and dates, never file contents.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToastView: View {
    let model: AppModel

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 12) {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? Color.danger : Color.lanternInk)
                Text(toast.message)
                    .font(.callout)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if !toast.undo.isEmpty {
                    Button("Put Back") {
                        model.putBack(toast.undo)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    model.toast = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.inkSecondary)
                .help("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.stroke))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, 20)
            .id(toast.id)
            .task(id: toast.id) {
                // Long enough to reach Put Back.
                try? await Task.sleep(for: .seconds(toast.undo.isEmpty ? 4 : 12))
                if model.toast?.id == toast.id { model.toast = nil }
            }
        }
    }
}
