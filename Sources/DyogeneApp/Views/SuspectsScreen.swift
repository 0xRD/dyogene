import DyogeneCore
import SwiftUI

/// Usual places where space can be won back, with what each one costs.
struct SuspectsScreen: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suspects")
                        .font(Typeface.display(26))
                    Text("Places that often hold space you can win back. Each says what it is and what removing it costs. Look before you remove.")
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: 640, alignment: .leading)
                }
                if model.isScanning {
                    ProgressView("Scanning…")
                } else if model.findings.isEmpty {
                    ContentUnavailableView("No usual suspects here", systemImage: "checkmark.seal",
                                           description: Text("Nothing from the known list was found in this scan. The Hoard may still show large forgotten items."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(model.findings) { finding in
                            SuspectCard(model: model, finding: finding)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct SuspectCard: View {
    let model: AppModel
    let finding: SuspectFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.rule.title)
                    .font(Typeface.display(18))
                Spacer()
                RiskBadge(risk: finding.rule.risk)
            }
            Text(Format.bytes(finding.size))
                .font(Typeface.display(30, weight: .medium))
            Text(finding.rule.explanation)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(Color.inkSecondary)
                Text(finding.rule.consequence)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let advice = finding.rule.advice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Color.lanternInk)
                    Text(advice)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let tree = model.tree {
                VStack(spacing: 0) {
                    ForEach(finding.nodes.prefix(4), id: \.self) { index in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tree[index].name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Text("Used \(Format.age(lastUsed: tree[index].lastUsed, now: model.now))")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            Spacer()
                            Text(Format.bytes(tree[index].size)).font(Typeface.data(11.5))
                            Button {
                                model.showOnMap(index)
                            } label: {
                                Image(systemName: "square.grid.3x3.square")
                            }
                            .buttonStyle(.borderless)
                            .help("Show on the map")
                            Button {
                                model.reveal(index)
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Show in Finder")
                        }
                        .padding(.vertical, 6)
                        if index != finding.nodes.prefix(4).last { Divider() }
                    }
                    if finding.nodes.count > 4 {
                        Text("and \(finding.nodes.count - 4) more")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(RoundedRectangle(cornerRadius: Metrics.corner).strokeBorder(Color.stroke))
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        let color: Color = switch risk {
        case .low: Color(nsColor: Palette.dustRamp[0])
        case .medium: Color.lantern
        case .high: Color.dangerFill
        }
        Text(risk.title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.22), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.6)))
    }
}
