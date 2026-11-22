import AppKit
import DyogeneCore
import QuartzCore
import SwiftUI

/// SwiftUI wrapper of the map. The values passed in are what triggers a redraw.
struct MapView: NSViewRepresentable {
    let model: AppModel
    let tree: FileTree?
    let treeVersion: Int
    let focus: Int
    let selection: Int?
    let lens: AppModel.Lens
    let scanning: Bool
    let settled: [SettledItem]
    let now: Double

    func makeNSView(context: Context) -> MapNSView {
        let view = MapNSView()
        view.model = model
        return view
    }

    func updateNSView(_ view: MapNSView, context: Context) {
        view.update(tree: tree, version: treeVersion, focus: focus, selection: selection, lens: lens,
                    scanning: scanning, settled: settled, now: now)
    }
}

/// Draws the treemap with Core Graphics and handles the mouse and keyboard precisely.
final class MapNSView: NSView {
    weak var model: AppModel?

    private var tree: FileTree?
    private var version = -1
    private var focus = FileTree.root
    private var selection: Int?
    private var lens: AppModel.Lens = .dust
    private var now = 0.0
    private var scanning = false
    private var settled: [SettledItem] = []
    private var settledAppearance: [String: CFTimeInterval] = [:]

    private var tiles: [MapTile] = []
    private var layoutSize: CGSize = .zero
    private var layoutVersion = -1
    private var layoutFocus = -1
    private var hovered: MapTile?
    private var mouse: CGPoint?

    private struct Transition {
        let rect: CGRect
        let zoomIn: Bool
        let start: CFTimeInterval
        let previous: [MapTile]
        static let duration: CFTimeInterval = 0.34
    }
    private var transition: Transition?
    private var displayLink: CADisplayLink?

    private static let grain = makeGrain()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: Updates

    func update(tree: FileTree?, version: Int, focus: Int, selection: Int?, lens: AppModel.Lens,
                scanning: Bool, settled: [SettledItem], now: Double) {
        let previousFocus = self.focus
        let focusChanged = focus != previousFocus && version == self.version && tree != nil
        let previousTiles = tiles
        self.tree = tree
        self.now = now
        self.selection = selection
        self.lens = lens
        self.scanning = scanning
        let time = CACurrentMediaTime()
        for item in settled where settledAppearance[item.name] == nil { settledAppearance[item.name] = time }
        if settled.isEmpty { settledAppearance = [:] }
        self.settled = settled
        if version != self.version { hovered = nil }
        self.version = version
        self.focus = focus
        relayoutIfNeeded()

        if focusChanged, let tree, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if tree.isAncestor(previousFocus, of: focus) {
                // Zoom in: the new map grows out of the tile that was clicked.
                if let rect = Self.rect(for: focus, in: previousTiles, tree: tree) {
                    transition = Transition(rect: rect, zoomIn: true, start: time, previous: previousTiles)
                }
            } else if tree.isAncestor(focus, of: previousFocus) {
                // Zoom out: the map pulls back from where we were.
                if let rect = Self.rect(for: previousFocus, in: tiles, tree: tree) {
                    transition = Transition(rect: rect, zoomIn: false, start: time, previous: [])
                }
            }
        }
        updateDisplayLink()
        needsDisplay = true
    }

    /// The tile of `index`, or of its closest drawn ancestor.
    private static func rect(for index: Int, in tiles: [MapTile], tree: FileTree) -> CGRect? {
        for ancestor in tree.lineage(of: index).reversed() {
            if let tile = tiles.first(where: { $0.node == ancestor }) { return tile.rect }
        }
        return nil
    }

    private func relayoutIfNeeded() {
        guard let tree else {
            tiles = []
            return
        }
        let size = bounds.size
        guard size != layoutSize || version != layoutVersion || focus != layoutFocus else { return }
        layoutSize = size
        layoutVersion = version
        layoutFocus = focus
        tiles = MapLayout.tiles(for: tree, focus: focus, in: bounds.insetBy(dx: 1, dy: 1))
        if let mouse { hovered = MapLayout.hit(mouse, in: tiles) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayoutIfNeeded()
        needsDisplay = true
    }

    private func updateDisplayLink() {
        let animating = transition != nil || (scanning && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if animating && displayLink == nil {
            let link = displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !animating, let link = displayLink {
            link.invalidate()
            displayLink = nil
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        if let transition, CACurrentMediaTime() - transition.start > Transition.duration {
            self.transition = nil
            updateDisplayLink()
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(Palette.canvas.cgColor)
            context.fill(bounds)
            if scanning || tree == nil {
                drawScan(context)
                return
            }
            guard let tree else { return }
            if let transition {
                let elapsed = CACurrentMediaTime() - transition.start
                let p = Self.easeOut(min(1, elapsed / Transition.duration))
                if transition.zoomIn {
                    context.saveGState()
                    context.setAlpha(1 - p)
                    drawTiles(transition.previous, tree: tree, context: context, interactive: false)
                    context.restoreGState()
                    let target = Self.lerp(transition.rect, bounds, p)
                    context.saveGState()
                    context.concatenate(Self.transform(from: bounds, to: target))
                    drawTiles(tiles, tree: tree, context: context, interactive: false)
                    context.restoreGState()
                } else {
                    let source = Self.lerp(transition.rect, bounds, p)
                    context.saveGState()
                    context.concatenate(Self.transform(from: source, to: bounds))
                    drawTiles(tiles, tree: tree, context: context, interactive: false)
                    context.restoreGState()
                }
            } else {
                drawTiles(tiles, tree: tree, context: context, interactive: true)
                drawLantern(context)
            }
        }
    }

    private func drawTiles(_ tiles: [MapTile], tree: FileTree, context: CGContext, interactive: Bool) {
        let dark = effectiveAppearance.isDark
        for tile in tiles {
            drawTile(tile, tree: tree, context: context, dark: dark)
        }
        guard interactive else { return }
        if let selection, let tile = tiles.last(where: { $0.node == selection }) {
            strokeHighlight(tile.rect, context: context, width: 2.5, glow: true)
        } else if let selection, let rect = Self.rect(for: selection, in: tiles, tree: tree), selection != focus {
            // Selected but too small to draw: mark the tile that holds it.
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [5, 4])
            strokeHighlight(rect, context: context, width: 1.5, glow: false)
            context.restoreGState()
        }
        if let hovered {
            drawHover(hovered, context: context)
        }
    }

    private func fill(for tile: MapTile, tree: FileTree) -> NSColor {
        guard let index = tile.node else {
            return Palette.plain.blended(withFraction: 0.35, of: Palette.canvas) ?? Palette.plain
        }
        let node = tree[index]
        switch lens {
        case .dust: return Palette.dust(Dust.level(lastUsed: node.lastUsed, now: now))
        case .kind: return Palette.kind(node.kind)
        case .plain:
            let step = CGFloat(tile.depth) * 0.08
            return Palette.plain.blended(withFraction: step, of: effectiveAppearance.isDark ? .white : .black) ?? Palette.plain
        }
    }

    private func drawTile(_ tile: MapTile, tree: FileTree, context: CGContext, dark: Bool) {
        let rect = tile.rect
        let radius = min(Metrics.tileCorner, rect.width / 4, rect.height / 4)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        var color = fill(for: tile, tree: tree)
        if tile.hasChildren {
            // Containers are darker so the gaps between their children read as structure.
            color = color.blended(withFraction: dark ? 0.45 : 0.22, of: dark ? Palette.night : NSColor(hex: 0x3A3550)) ?? color
        }
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()

        context.saveGState()
        context.addPath(path)
        context.clip()
        if !tile.hasChildren && rect.height > 6 {
            // Cushion: a soft light from above makes each tile read as one object.
            let top = NSColor.white.withAlphaComponent(dark ? 0.10 : 0.22).cgColor
            let bottom = NSColor.black.withAlphaComponent(dark ? 0.16 : 0.08).cgColor
            if let gradient = CGGradient(colorsSpace: nil, colors: [top, NSColor.clear.cgColor, bottom] as CFArray, locations: [0, 0.5, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
            }
        }
        if lens == .dust, let index = tile.node, !tile.hasChildren, let grain = Self.grain {
            let level = Dust.level(lastUsed: tree[index].lastUsed, now: now)
            if level > 0.45 {
                context.setAlpha(min(0.9, (level - 0.45) * 1.6))
                context.draw(grain, in: CGRect(x: 0, y: 0, width: 96, height: 96), byTiling: true)
                context.setAlpha(1)
            }
        }
        context.restoreGState()

        drawLabel(tile, tree: tree, fill: color)
    }

    private func drawLabel(_ tile: MapTile, tree: FileTree, fill: NSColor) {
        let rect = tile.rect
        let ink = fill.luminance > 0.33 ? NSColor(hex: 0x1F2035) : NSColor(hex: 0xF7F3EA)
        let name: String
        let size: UInt64
        if let index = tile.node {
            name = tree[index].name
            size = tree[index].size
        } else {
            name = tile.groupCount == 1 ? "1 smaller item" : "\(tile.groupCount) smaller items"
            size = tile.groupSize
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: tile.depth == 0 ? 12.5 : 11.5, weight: .semibold),
            .foregroundColor: ink, .paragraphStyle: paragraph,
        ]
        let sizeAttributes: [NSAttributedString.Key: Any] = [
            .font: Typeface.nsData(11), .foregroundColor: ink.withAlphaComponent(0.72), .paragraphStyle: paragraph,
        ]
        let sizeText = Format.bytes(size)
        if tile.hasChildren {
            // One line in the header: name, then size.
            let sizeWidth = (sizeText as NSString).size(withAttributes: sizeAttributes).width
            guard rect.width > 50 else { return }
            let nameRect = CGRect(x: rect.minX + 6, y: rect.minY + 3, width: max(0, rect.width - sizeWidth - 18), height: 15)
            (name as NSString).draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttributes)
            if rect.width > sizeWidth + 60 {
                (sizeText as NSString).draw(at: CGPoint(x: rect.maxX - sizeWidth - 6, y: rect.minY + 4), withAttributes: sizeAttributes)
            }
            return
        }
        guard rect.width >= 44, rect.height >= 18 else { return }
        let lineWidth = rect.width - 12
        let nameRect = CGRect(x: rect.minX + 6, y: rect.minY + 5, width: lineWidth, height: 15)
        (name as NSString).draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttributes)
        if rect.height >= 36 {
            let sizeRect = CGRect(x: rect.minX + 6, y: rect.minY + 20, width: lineWidth, height: 14)
            (sizeText as NSString).draw(with: sizeRect, options: [.usesLineFragmentOrigin], attributes: sizeAttributes)
        }
    }

    private func strokeHighlight(_ rect: CGRect, context: CGContext, width: CGFloat, glow: Bool) {
        context.saveGState()
        if glow { context.setShadow(offset: .zero, blur: 10, color: Palette.lantern.withAlphaComponent(0.8).cgColor) }
        let inset = rect.insetBy(dx: width / 2, dy: width / 2)
        let radius = min(Metrics.tileCorner, inset.width / 4, inset.height / 4)
        context.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setStrokeColor(Palette.lantern.cgColor)
        context.setLineWidth(width)
        context.strokePath()
        context.restoreGState()
    }

    /// The tile under the cursor is lit from the cursor, like a lantern held over it.
    private func drawHover(_ tile: MapTile, context: CGContext) {
        guard let mouse else { return }
        let rect = tile.hasChildren ? CGRect(x: tile.rect.minX, y: tile.rect.minY, width: tile.rect.width, height: min(tile.rect.height, 20)) : tile.rect
        let radius = min(Metrics.tileCorner, rect.width / 4, rect.height / 4)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        let reach = max(rect.width, rect.height) * 0.9 + 40
        let colors = [Palette.glow.withAlphaComponent(0.55).cgColor, Palette.glow.withAlphaComponent(0.12).cgColor,
                      Palette.glow.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.45, 1]) {
            context.drawRadialGradient(gradient, startCenter: mouse, startRadius: 0, endCenter: mouse, endRadius: reach, options: [])
        }
        context.restoreGState()
        if selection == nil || tile.node != selection {
            strokeHighlight(tile.hasChildren ? tile.rect : rect, context: context, width: 1.5, glow: false)
        }
    }

    /// Outside the lantern's reach the map dims slightly (dark mode only).
    private func drawLantern(_ context: CGContext) {
        guard let mouse, effectiveAppearance.isDark else { return }
        let colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.20).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) else { return }
        let reach = max(bounds.width, bounds.height) * 0.75
        context.drawRadialGradient(gradient, startCenter: mouse, startRadius: 160, endCenter: mouse, endRadius: reach,
                                   options: [.drawsAfterEndLocation])
    }

    /// While scanning, finished top-level folders settle into a provisional map under a moving light.
    private func drawScan(_ context: CGContext) {
        let time = CACurrentMediaTime()
        let items = settled.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let rects = Treemap.squarify(items.map { Double($0.size) }, in: bounds.insetBy(dx: 1, dy: 1))
        let dark = effectiveAppearance.isDark
        for (item, rect) in zip(items, rects) {
            let inset = rect.insetBy(dx: 1, dy: 1)
            guard inset.width > 1, inset.height > 1 else { continue }
            let appeared = settledAppearance[item.name] ?? time
            let alpha = min(1, (time - appeared) / 0.45)
            let color = lens == .kind ? Palette.kind(item.kind) : Palette.dust(Dust.level(lastUsed: item.lastUsed, now: Date().timeIntervalSince1970))
            context.saveGState()
            context.setAlpha(alpha * 0.85)
            let radius = min(Metrics.tileCorner, inset.width / 4, inset.height / 4)
            context.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(color.cgColor)
            context.fillPath()
            if inset.width > 60 && inset.height > 36 {
                let ink = color.luminance > 0.33 ? NSColor(hex: 0x1F2035) : NSColor(hex: 0xF7F3EA)
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: ink]
                (item.name as NSString).draw(with: CGRect(x: inset.minX + 6, y: inset.minY + 5, width: inset.width - 12, height: 15),
                                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
                let sizeAttributes: [NSAttributedString.Key: Any] = [.font: Typeface.nsData(11), .foregroundColor: ink.withAlphaComponent(0.7)]
                (Format.bytes(item.size) as NSString).draw(at: CGPoint(x: inset.minX + 6, y: inset.minY + 20), withAttributes: sizeAttributes)
            }
            context.restoreGState()
        }
        guard scanning, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // The lantern looking around.
        let center = CGPoint(x: bounds.midX + sin(time * 0.9) * bounds.width * 0.32,
                             y: bounds.midY + cos(time * 0.6) * bounds.height * 0.22)
        let colors = [Palette.glow.withAlphaComponent(dark ? 0.32 : 0.45).cgColor, Palette.lantern.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: min(bounds.width, bounds.height) * 0.45, options: [])
        }
    }

    // MARK: Mouse and keyboard

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouse = point
        let hit = transition == nil && !scanning ? MapLayout.hit(point, in: tiles) : nil
        hovered = hit
        if let hit {
            model?.hover = AppModel.Hover(node: hit.node, parent: hit.parent, groupCount: hit.groupCount,
                                          groupSize: hit.groupSize, location: point, mapSize: bounds.size)
        } else if model?.hover != nil {
            model?.hover = nil
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        hovered = nil
        model?.hover = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model, !scanning, tree != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let tile = MapLayout.hit(point, in: tiles) else {
            model.select(nil)
            return
        }
        if event.clickCount >= 2 {
            model.zoom(into: tile.node ?? tile.parent)
        } else {
            model.select(tile.node)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let tree, !scanning else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let tile = MapLayout.hit(point, in: tiles) else { return nil }
        let index = tile.node ?? tile.parent
        model.select(index)
        return ItemMenu.make(for: index, tree: tree, model: model, isGroup: tile.node == nil)
    }

    override func keyDown(with event: NSEvent) {
        guard let model, !scanning else { return super.keyDown(with: event) }
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 36, 76: // Return, Enter
            if let selection = model.selection { model.zoom(into: selection) }
        case 53: // Escape
            if model.selection != nil && model.selection != model.focus { model.select(nil) } else { model.zoomOut() }
        case 126 where command: // Cmd+Up
            model.zoomOut()
        case 125 where command: // Cmd+Down
            if let selection = model.selection { model.zoom(into: selection) }
        case 49: // Space
            if let selection = model.selection { model.quickLook(selection) }
        case 51 where command: // Cmd+Delete: opens the Trash sheet, which still needs a hold
            if let selection = model.selection { model.requestRemoval([selection], mode: .trash) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Helpers

    private static func easeOut(_ t: Double) -> CGFloat { CGFloat(1 - pow(1 - t, 3)) }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// Maps `source` onto `target`.
    private static func transform(from source: CGRect, to target: CGRect) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let sx = target.width / source.width
        let sy = target.height / source.height
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: target.minX - source.minX * sx, ty: target.minY - source.minY * sy)
    }

    /// Sand-coloured specks, tiled over old tiles: the dust.
    private static func makeGrain() -> CGImage? {
        let size = 96
        var random = SystemRandomNumberGenerator()
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for _ in 0..<420 {
            let x = CGFloat(Int.random(in: 0..<size, using: &random))
            let y = CGFloat(Int.random(in: 0..<size, using: &random))
            let light = Bool.random(using: &random)
            let alpha = CGFloat.random(in: 0.12...0.38, using: &random)
            context.setFillColor(light ? NSColor(hex: 0xF3E8D2, alpha: alpha).cgColor : NSColor(hex: 0x3B3226, alpha: alpha).cgColor)
            let r = CGFloat.random(in: 0.5...1.3, using: &random)
            context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        return context.makeImage()
    }
}

/// The context menu of an item. Destructive entries are last, in a submenu, and only open a
/// confirmation sheet.
@MainActor
enum ItemMenu {
    static func make(for index: Int, tree: FileTree, model: AppModel, isGroup: Bool) -> NSMenu {
        let menu = NSMenu()
        let node = tree[index]
        menu.addItem(ClosureMenuItem(isGroup ? "Show Folder in Finder" : "Show in Finder", symbol: "folder") { model.reveal(index) })
        if !isGroup {
            menu.addItem(ClosureMenuItem("Open", symbol: "arrow.up.forward.app") { model.open(index) })
            if !node.isDirectory || node.isPackage {
                menu.addItem(ClosureMenuItem("Quick Look", symbol: "eye") { model.quickLook(index) })
            }
        }
        if node.isDirectory && !node.isPackage && index != model.focus {
            menu.addItem(ClosureMenuItem("Zoom In", symbol: "plus.magnifyingglass") { model.zoom(into: index) })
        }
        menu.addItem(ClosureMenuItem("Copy Path", symbol: "doc.on.doc") { model.copyPath(index) })
        if !isGroup && index != FileTree.root {
            menu.addItem(.separator())
            let remove = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
            remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            let submenu = NSMenu()
            for mode in RemovalMode.allCases {
                submenu.addItem(ClosureMenuItem(mode.title + "…", symbol: nil) { model.requestRemoval([index], mode: mode) })
            }
            remove.submenu = submenu
            menu.addItem(remove)
        }
        return menu
    }
}

@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, symbol: String?, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
