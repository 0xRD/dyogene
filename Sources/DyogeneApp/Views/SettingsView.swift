import DyogeneCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let draft = SettingsDraft()

    var body: some View {
        Form {
            Section("Scanning") {
                LabeledContent("Scan") {
                    Text(model.scanRoot).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                LabeledContent("Skip these folders") {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.exclusions.isEmpty {
                            Text("None").foregroundStyle(Color.inkSecondary)
                        }
                        ForEach(model.exclusions, id: \.self) { path in
                            HStack {
                                Text(path).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button("Remove", systemImage: "minus.circle") {
                                    model.exclusions.removeAll { $0 == path }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Folder…") { addExclusion() }
                    }
                }
            }
            Section("Privacy") {
                LabeledContent("Full Disk Access") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.fullDiskAccess ? "Allowed: every folder you can open is scanned."
                             : "Not allowed: folders macOS protects (Mail, Messages, other apps' data) are skipped.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Privacy Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                            Button("Check Again") { model.fullDiskAccess = FullDiskAccess.isGranted }
                        }
                    }
                }
                LabeledContent("Network") {
                    Text("None. Dyogène has no network code: no updates check, no analytics.")
                }
                LabeledContent("Scan results") {
                    Text("Kept in memory only, gone when you quit.")
                }
            }
            Section("Claude skill") {
                LabeledContent("Command line tool") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Bundle.main.bundlePath + "/Contents/Helpers/dyogene")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Gives names, sizes and dates as JSON. It cannot delete anything. Install the skill with scripts/install-skill.sh from the source folder.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Skip"
        if panel.runModal() == .OK, let url = panel.url, !model.exclusions.contains(url.path) {
            model.exclusions.append(url.path)
        }
    }
}

@Observable final class SettingsDraft {}
