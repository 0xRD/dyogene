import DyogeneCore
import SwiftUI

/// Everything about the selected item (or the focused folder), and what can be done with it.
struct Inspector: View {
    let model: AppModel

    var body: some View {
        if let tree = model.tree {
            let index = model.inspected
            let node = tree[index]
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(index, node: node, tree: tree)
                    facts(index, node: node, tree: tree)
                    let remark = Remark.about(index, in: tree, now: model.now)
                    SageSays(text: remark.text, expression: DyogeneExpression(remark.mood))
                    if node.isDirectory && !node.flags.contains(.smallGroup) && !tree.visibleChildren(of: index).isEmpty {
                        contents(index, tree: tree)
                    }
                    notes(node)
                    actions(index, node: node)
                }
                .padding(18)
            }
            .background(Color.panel)
        }
    }

    private func header(_ index: Int, node: Node, tree: FileTree) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: Palette.kind(node.kind)))
                    .frame(width: 9, height: 9)
                Text(kindLine(node))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.inkSecondary)
            }
            Text(index == FileTree.root ? ScanLocation.title(for: tree.rootPath) : node.name)
                .font(Typeface.display(21))
                .foregroundStyle(Color.ink)
                .lineLimit(3)
                .textSelection(.enabled)
            Text(tree.displayPath(of: index))
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(Format.bytes(node.size))
                .font(Typeface.display(34, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(.top, 6)
            if let parent = tree.parent(of: index) {
                Text("\(Format.percent(node.size, of: tree[parent].size)) of \(parent == FileTree.root ? ScanLocation.title(for: tree.rootPath) : tree[parent].name)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func kindLine(_ node: Node) -> String {
        if node.flags.contains(.smallGroup) { return "Small files, grouped" }
        if node.isPackage { return "\(node.kind.title), shown as one item" }
        if node.isDirectory { return node.kind == .other ? "Folder" : "Folder, mostly \(node.kind.title.lowercased())" }
        return node.kind.title
    }

    private func facts(_ index: Int, node: Node, tree: FileTree) -> some View {
        let used = model.lastUsed(index)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color(nsColor: Palette.dust(Dust.level(lastUsed: used.date, now: model.now))))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.stroke))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Used \(Format.age(lastUsed: used.date, now: model.now))")
                        .font(.system(size: 13, weight: .semibold))
                    Text(used.date > 0 ? "\(Format.date(used.date)), \(node.isDirectory && !node.isPackage ? "newest file inside" : used.source.title)" : "No date recorded")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            if node.isDirectory || node.flags.contains(.smallGroup) {
                fact("doc.on.doc", "\(Format.count(node.itemCount)) \(node.itemCount == 1 ? "file" : "files")")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 12).foregroundStyle(Color.inkSecondary)
            Text(text).font(.system(size: 12))
        }
    }

    private func contents(_ index: Int, tree: FileTree) -> some View {
        let children = Array(tree.visibleChildren(of: index).prefix(6))
        let largest = Double(children.first.map { tree[$0].size } ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Largest inside")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
            ForEach(children, id: \.self) { child in
                Button {
                    model.zoom(into: index)
                    model.select(child)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(tree[child].name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(tree[child].size)).font(Typeface.data(11.5)).foregroundStyle(Color.inkSecondary)
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill(Color(nsColor: Palette.dust(Dust.level(lastUsed: tree[child].lastUsed, now: model.now))))
                                .frame(width: max(3, geometry.size.width * Double(tree[child].size) / largest))
                        }
                        .frame(height: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func notes(_ node: Node) -> some View {
        let lines = noteLines(node)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "info.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func noteLines(_ node: Node) -> [String] {
        var lines: [String] = []
        if node.flags.contains(.inCloud) { lines.append("Stored in iCloud: it takes no space on this Mac.") }
        if node.flags.contains(.hardLink) { lines.append("Another name of a file counted elsewhere.") }
        if node.flags.contains(.needsAccess) { lines.append("Protected by macOS. Allow Full Disk Access to see inside.") }
        if node.flags.contains(.unreadable) { lines.append("Dyogène could not read this folder.") }
        if node.flags.contains(.mountPoint) { lines.append("Another disk is mounted here. Scan it on its own.") }
        if node.flags.contains(.smallGroup) { lines.append("Files too small to list one by one. Show the folder in Finder to see them.") }
        return lines
    }

    @ViewBuilder private func actions(_ index: Int, node: Node) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.reveal(index)
            } label: {
                Label(node.flags.contains(.smallGroup) ? "Show Folder in Finder" : "Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.lantern)
            .foregroundStyle(Color(nsColor: NSColor(hex: 0x1F2035)))
            .controlSize(.large)
            .help("Select it in a Finder window")

            if node.isActionable {
                HStack(spacing: 8) {
                    Button("Open") { model.open(index) }
                    if !node.isDirectory || node.isPackage {
                        Button("Quick Look") { model.quickLook(index) }
                    }
                    Button("Copy Path") { model.copyPath(index) }
                }
                .controlSize(.small)
            }

            if node.isActionable && index != FileTree.root {
                Divider().padding(.vertical, 6)
                Menu {
                    ForEach(RemovalMode.allCases, id: \.self) { mode in
                        Button(mode.title + "…") { model.requestRemoval([index], mode: mode) }
                    }
                } label: {
                    Label("Remove…", systemImage: "trash")
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(Color.danger)
                .fixedSize()
                .help("Opens a confirmation. Nothing is removed until you hold the button.")
            }
        }
    }
}
