import AppKit

/// DYOGENE_SNAPSHOT=/path/out.png renders the main window into a PNG a few seconds after launch,
/// then quits. For design reviews and README images (with DYOGENE_DEMO=1 only).
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["DYOGENE_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["DYOGENE_SNAPSHOT_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let size = ProcessInfo.processInfo.environment["DYOGENE_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }),
               size.count == 2, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                window.setContentSize(NSSize(width: size[0], height: size[1]))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                capture(to: path)
                if ProcessInfo.processInfo.environment["DYOGENE_SNAPSHOT_KEEP"] != "1" { exit(0) }
            }
        }
    }

    private static func capture(to path: String) {
        // Sheets are separate windows: capture the topmost visible one.
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        guard let main = windows.first(where: { $0.sheetParent == nil && $0.styleMask.contains(.titled) }),
              let frameView = main.contentView?.superview else { return }
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        var image = rep.cgImage
        if let sheet = main.attachedSheet, let sheetView = sheet.contentView?.superview,
           let sheetRep = sheetView.bitmapImageRepForCachingDisplay(in: sheetView.bounds), let base = image {
            sheetView.cacheDisplay(in: sheetView.bounds, to: sheetRep)
            let scale = CGFloat(base.width) / frameView.bounds.width
            let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
            context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            if let overlay = sheetRep.cgImage {
                let width = sheetView.bounds.width * scale
                let height = sheetView.bounds.height * scale
                let x = (CGFloat(base.width) - width) / 2
                let y = CGFloat(base.height) - height - 52 * scale
                context.draw(overlay, in: CGRect(x: x, y: y, width: width, height: height))
            }
            image = context.makeImage()
        }
        guard let final = image else { return }
        let output = NSBitmapImageRep(cgImage: final)
        try? output.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
