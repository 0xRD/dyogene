import DyogeneCore
import SwiftUI

struct MapScreen: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let volume = model.volume, let tree = model.tree, !model.isScanning {
                    VolumeGauge(volume: volume, scanned: tree.totalSize, rootTitle: ScanLocation.title(for: tree.rootPath),
                                fullDiskAccess: model.fullDiskAccess || model.isDemo)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                if model.tree != nil && !model.isScanning {
                    Breadcrumb(model: model)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                ZStack {
                    MapView(model: model, tree: model.tree, treeVersion: model.treeVersion, focus: model.focus,
                            selection: model.selection, lens: model.lens, scanning: model.isScanning,
                            settled: model.settled, now: model.now)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.corner).strokeBorder(Color.stroke))
                    LanternCard(model: model)
                    if model.isScanning { ScanStatus(model: model) }
                }
                .padding(.horizontal, 16)
                if !model.isScanning {
                    Legend(model: model)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                } else {
                    Spacer().frame(height: 16)
                }
            }
            if model.tree != nil && !model.isScanning {
                Divider()
                Inspector(model: model)
                    .frame(width: Metrics.inspectorWidth)
            }
        }
    }
}

/// Where the space of the disk goes, and how much of it this scan could see.
struct VolumeGauge: View {
    let volume: VolumeUsage
    let scanned: UInt64
    let rootTitle: String
    let fullDiskAccess: Bool

    var body: some View {
        let total = Double(max(volume.total, 1))
        let seen = min(scanned, volume.used)
        let notSeen = volume.used - seen
        let purgeable = min(volume.purgeable, volume.free)
        let free = volume.free - purgeable
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.name)
                    .font(Typeface.display(17))
                Text("\(Format.bytes(volume.free)) free of \(Format.bytes(volume.total))")
                    .font(Typeface.data(12))
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    segment(Color(nsColor: Palette.dust(0.15)), Double(seen) / total, geometry.size.width)
                    segment(Color.inkSecondary.opacity(0.35), Double(notSeen) / total, geometry.size.width)
                    segment(Color.lantern.opacity(0.35), Double(purgeable) / total, geometry.size.width)
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .background(Color.inset, in: Capsule())
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(spacing: 16) {
                key(Color(nsColor: Palette.dust(0.15)), "\(rootTitle) \(Format.bytes(seen))",
                    help: "What this scan measured.")
                key(Color.inkSecondary.opacity(0.35), "Not seen \(Format.bytes(notSeen))",
                    help: fullDiskAccess
                        ? "macOS itself, other user accounts, local snapshots and folders outside the scan."
                        : "macOS itself, other user accounts, local snapshots, folders outside the scan, and folders macOS protects (allow Full Disk Access to see them).")
                key(Color.lantern.opacity(0.35), "Purgeable \(Format.bytes(purgeable))",
                    help: "Space macOS frees by itself when needed (caches, local snapshots).")
                key(Color.inset, "Free \(Format.bytes(free))", help: "Free right now.")
                Spacer()
            }
            .font(Typeface.data(11))
            .foregroundStyle(Color.inkSecondary)
        }
    }

    private func segment(_ color: Color, _ fraction: Double, _ width: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: max(0, width * fraction - 2))
    }

    private func key(_ color: Color, _ text: String, help: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.stroke))
            Text(text)
        }
        .help(help)
    }
}

struct Breadcrumb: View {
    let model: AppModel

    var body: some View {
        if let tree = model.tree {
            HStack(spacing: 4) {
                Button {
                    model.zoomOut()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .disabled(model.focus == FileTree.root)
                .help("Zoom out (Escape or Cmd+Up)")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let lineage = tree.lineage(of: model.focus)
                        ForEach(Array(lineage.enumerated()), id: \.element) { position, index in
                            if position > 0 {
                                Image(systemName: "chevron.compact.right")
                                    .foregroundStyle(Color.inkSecondary)
                                    .font(.system(size: 11))
                            }
                            Button {
                                model.focus = index
                                model.selection = nil
                            } label: {
                                Text(index == FileTree.root ? ScanLocation.title(for: tree.rootPath) : tree[index].name)
                                    .font(.system(size: 13, weight: index == model.focus ? .semibold : .regular))
                                    .foregroundStyle(index == model.focus ? Color.ink : Color.inkSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(index == model.focus ? Color.inset : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                Text(Format.bytes(tree[model.focus].size))
                    .font(Typeface.data(13, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
        }
    }
}

/// What the colours mean, under the map.
struct Legend: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            switch model.lens {
            case .dust:
                Text("Last used")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                HStack(spacing: 0) {
                    ForEach(Array(Dust.legend.enumerated()), id: \.offset) { position, mark in
                        VStack(alignment: .leading, spacing: 3) {
                            Rectangle()
                                .fill(Color(nsColor: Palette.dust(Dust.level(lastUsed: model.now - mark.age, now: model.now))))
                                .frame(height: 8)
                            Text(mark.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .frame(width: 74)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            case .kind:
                ForEach(presentKinds, id: \.self) { kind in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: Palette.kind(kind))).frame(width: 10, height: 10)
                        Text(kind.title).font(.system(size: 11)).foregroundStyle(Color.inkSecondary)
                    }
                }
            case .plain:
                Text("Area is size on disk.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Text("Double-click to zoom in, Escape to zoom out")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary.opacity(0.8))
        }
    }

    private var presentKinds: [Kind] {
        guard let tree = model.tree else { return [] }
        var sizes: [Kind: UInt64] = [:]
        for child in tree.visibleChildren(of: model.focus) { sizes[tree[child].kind, default: 0] += tree[child].size }
        return sizes.sorted { $0.value > $1.value }.map(\.key).prefix(7).map { $0 }
    }
}

/// The card that follows the lantern (the cursor) over the map.
struct LanternCard: View {
    let model: AppModel

    var body: some View {
        if let hover = model.hover, let tree = model.tree, !model.isScanning {
            let content = card(hover, tree: tree)
            GeometryReader { _ in
                content
                    .fixedSize()
                    .alignmentGuide(.leading) { dimensions in
                        let x = hover.location.x + 18
                        return x + dimensions.width > hover.mapSize.width - 8 ? -(hover.location.x - dimensions.width - 14) : -x
                    }
                    .alignmentGuide(.top) { dimensions in
                        let y = hover.location.y + 18
                        return y + dimensions.height > hover.mapSize.height - 8 ? -(hover.location.y - dimensions.height - 12) : -y
                    }
            }
            .allowsHitTesting(false)
            .padding(.horizontal, 0)
        }
    }

    @ViewBuilder private func card(_ hover: AppModel.Hover, tree: FileTree) -> some View {
        let parentSize = tree[hover.parent].size
        VStack(alignment: .leading, spacing: 4) {
            if let index = hover.node {
                let node = tree[index]
                Text(node.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: 280, alignment: .leading)
                HStack(spacing: 8) {
                    Text(Format.bytes(node.size)).font(Typeface.data(13, weight: .medium))
                    Text("\(Format.percent(node.size, of: parentSize)) of \(hover.parent == FileTree.root ? ScanLocation.title(for: tree.rootPath) : tree[hover.parent].name)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(nsColor: Palette.dust(Dust.level(lastUsed: node.lastUsed, now: model.now))))
                        .frame(width: 8, height: 8)
                    Text("Used \(Format.age(lastUsed: node.lastUsed, now: model.now))")
                    if node.isDirectory && !node.flags.contains(.smallGroup) {
                        Text("\(Format.count(node.itemCount)) files").foregroundStyle(Color.inkSecondary)
                    }
                }
                .font(.system(size: 11.5))
            } else {
                Text(hover.groupCount == 1 ? "1 smaller item" : "\(hover.groupCount) smaller items")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Format.bytes(hover.groupSize)) together, too small to draw one by one. Zoom in or see the Hoard.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.lantern.opacity(0.45)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

/// Counters shown over the map while scanning.
struct ScanStatus: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            Text("Looking through \(ScanLocation.title(for: model.scanRoot))…")
                .font(Typeface.display(20))
            HStack(spacing: 14) {
                Text("\(Format.count(model.scannedFiles)) files")
                Text(Format.bytes(model.scannedBytes))
            }
            .font(Typeface.data(13))
            .foregroundStyle(Color.inkSecondary)
            Text("Names, sizes and dates only. Nothing leaves this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.stroke))
    }
}
