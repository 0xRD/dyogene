import DyogeneCore
import SwiftUI

/// The heaviest things, as a list you can act on in one click.
struct HoardScreen: View {
    @Bindable var model: AppModel

    private static let ages: [(String, Double)] = [("Any time", 0), ("6 months", 182 * Dust.day), ("1 year", 365 * Dust.day),
                                                   ("2 years", 730 * Dust.day), ("3 years", 1095 * Dust.day)]
    private static let sizes: [(String, UInt64)] = [("Any size", 0), ("100 MB", 100_000_000), ("1 GB", 1_000_000_000), ("10 GB", 10_000_000_000)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let tree = model.tree, !model.isScanning {
                let items = model.hoardItems
                if items.isEmpty {
                    ContentUnavailableView("Nothing matches", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try a shorter time or a smaller size."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            let largest = Double(tree[items[0]].size)
                            ForEach(Array(items.enumerated()), id: \.element) { rank, index in
                                HoardRow(model: model, tree: tree, index: index, rank: rank + 1, largest: largest)
                                Divider().padding(.leading, 52)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            } else {
                ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hoard")
                    .font(Typeface.display(26))
                Text(model.hoardFilter.mode == .items ? "The heaviest files, apps and libraries" : "Folders whose weight is the files they hold")
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
            }
            HStack(spacing: 14) {
                Picker("Show", selection: $model.hoardFilter.mode) {
                    Text("Items").tag(Hoard.Mode.items)
                    Text("Folders").tag(Hoard.Mode.folders)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .labelsHidden()

                Picker("Unused for", selection: $model.hoardFilter.unusedFor) {
                    ForEach(Self.ages, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 170)

                Picker("Kind", selection: $model.hoardFilter.kind) {
                    Text("All kinds").tag(Kind?.none)
                    ForEach(Kind.allCases, id: \.self) { Text($0.title).tag(Kind?.some($0)) }
                }
                .frame(width: 230)

                Picker("At least", selection: $model.hoardFilter.minimumSize) {
                    ForEach(Self.sizes, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 150)
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct HoardRow: View {
    let model: AppModel
    let tree: FileTree
    let index: Int
    let rank: Int
    let largest: Double

    var body: some View {
        let node = tree[index]
        let used = model.lastUsed(index)
        let dust = Color(nsColor: Palette.dust(Dust.level(lastUsed: used.date, now: model.now)))
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(Typeface.data(11))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: Palette.kind(node.kind))).frame(width: 8, height: 8)
                        .help(node.kind.title)
                    Text(node.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
                Text(tree.relativePath(of: index).isEmpty ? tree.rootPath : (tree.relativePath(of: index) as NSString).deletingLastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                GeometryReader { geometry in
                    Capsule().fill(dust).frame(width: max(3, geometry.size.width * Double(node.size) / largest))
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Format.bytes(node.size))
                .font(Typeface.data(13, weight: .semibold))
                .frame(width: 80, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.age(lastUsed: used.date, now: model.now)).font(.system(size: 12))
                Text(used.source == .spotlight ? "opened" : "read or changed")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(width: 104, alignment: .trailing)
            .help(used.date > 0 ? "\(Format.date(used.date)), \(used.source.title)" : "No date recorded")

            Button {
                model.reveal(index)
            } label: {
                Image(systemName: "folder")
            }
            .help("Show in Finder")

            Menu {
                Button("Show on Map") { model.showOnMap(index) }
                Button("Open") { model.open(index) }
                Button("Quick Look") { model.quickLook(index) }
                Button("Copy Path") { model.copyPath(index) }
                Divider()
                Menu("Remove") {
                    ForEach(RemovalMode.allCases, id: \.self) { mode in
                        Button(mode.title + "…") { model.requestRemoval([index], mode: mode) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.showOnMap(index) }
    }
}
