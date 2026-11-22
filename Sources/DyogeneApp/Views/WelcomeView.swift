import DyogeneCore
import SwiftUI

/// First screen: what Dyogène does, where to look, and what it will never do.
struct WelcomeView: View {
    let model: AppModel
    var error: String?

    var body: some View {
        ZStack {
            // The lantern's light, falling on the page.
            RadialGradient(colors: [Color.glow.opacity(0.28), Color.lantern.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                HStack(alignment: .center, spacing: 6) {
                    SageFigure(expression: error == nil ? .calm : .curious)
                        .frame(width: 170, height: 170)
                    Text(error == nil
                         ? "I am Dyogène. I own a jar and a lantern.\nShall we see what you own?"
                         : "Hm. Something got in the way.")
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundStyle(Color.ink)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(SpeechBubble().fill(Color.panel))
                        .overlay(SpeechBubble().stroke(Color.stroke))
                        .padding(.bottom, 60)
                }
                .padding(.trailing, 90)

                VStack(spacing: 10) {
                    Text("Dyogène")
                        .font(Typeface.display(44))
                        .foregroundStyle(Color.ink)
                    Text("Shine a light on what your Mac keeps.")
                        .font(Typeface.display(19, weight: .regular))
                        .foregroundStyle(Color.inkSecondary)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: 460)
                }

                VStack(spacing: 10) {
                    Button {
                        model.scan(NSHomeDirectory())
                    } label: {
                        Text("Scan My Home Folder")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minWidth: 220)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.lantern)
                    .foregroundStyle(Color(nsColor: NSColor(hex: 0x1F2035)))
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    HStack(spacing: 16) {
                        Button("Scan the Whole Mac") { model.scan(ScanLocation.wholeMac) }
                        Button("Choose a Folder…") { ScanLocation.choose(model) }
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.lanternInk)
                }

                VStack(alignment: .leading, spacing: 12) {
                    promise("lock.shield", "Everything stays on this Mac",
                            "No network access. Dyogène reads names, sizes and dates, never what is inside your files.")
                    promise("hand.raised", "Nothing is removed by accident",
                            "Removing anything takes a confirmation and a long press. The Trash comes first.")
                    if !model.fullDiskAccess {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock")
                                .frame(width: 22)
                                .foregroundStyle(Color.lanternInk)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("For the full picture, allow Full Disk Access")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Without it, folders macOS protects (Mail, Messages, other apps' data) are skipped and counted as not seen. You can add it any time.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.inkSecondary)
                                Button("Open Privacy Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                                    .buttonStyle(.link)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.lanternInk)
                            }
                        }
                    }
                }
                .frame(maxWidth: 470)
                .padding(18)
                .background(Color.panel.opacity(0.8), in: RoundedRectangle(cornerRadius: Metrics.corner))
                .overlay(RoundedRectangle(cornerRadius: Metrics.corner).strokeBorder(Color.stroke))
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Color.lanternInk)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
