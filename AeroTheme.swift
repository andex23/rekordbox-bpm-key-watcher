import AppKit

enum AeroTheme {
    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "SegoeUI-Bold" : "SegoeUI", size: size) ?? NSFont(name: bold ? "Tahoma-Bold" : "Tahoma", size: size) ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }
    static func apply(to window: NSWindow) {
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.64, green: 0.82, blue: 0.96, alpha: 1)
        window.isOpaque = false
        let glass = AeroGlassView(frame: window.contentView!.bounds)
        glass.autoresizingMask = [.width, .height]
        window.contentView = glass
    }
}

final class AeroGlassView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow; blendingMode = .behindWindow; state = .active
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.white.withAlphaComponent(0.75).cgColor
        layer?.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGradient(colors: [NSColor(calibratedRed: 0.89, green: 0.96, blue: 1, alpha: 0.94), NSColor(calibratedRed: 0.48, green: 0.72, blue: 0.93, alpha: 0.84)])?.draw(in: bounds, angle: 90)
        let shine = NSRect(x: 1, y: bounds.height * 0.52, width: bounds.width - 2, height: bounds.height * 0.48 - 1)
        NSGradient(starting: .white.withAlphaComponent(0.02), ending: .white.withAlphaComponent(0.5))?.draw(in: shine, angle: 90)
        NSColor.white.withAlphaComponent(0.65).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).stroke()
    }
}

final class AeroButton: NSButton {
    override var intrinsicContentSize: NSSize {
        let size = (title as NSString).size(withAttributes: [.font: AeroTheme.font(12)])
        return NSSize(width: max(70, size.width + 24), height: 27)
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        let pressed = cell?.isHighlighted == true
        let top = pressed ? NSColor(calibratedRed: 0.67, green: 0.81, blue: 0.93, alpha: 1) : .white
        let bottom = NSColor(calibratedRed: 0.73, green: 0.82, blue: 0.89, alpha: isEnabled ? 1 : 0.6)
        NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)
        NSColor(calibratedRed: 0.29, green: 0.42, blue: 0.53, alpha: 1).setStroke(); shape.stroke()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: AeroTheme.font(12), .foregroundColor: isEnabled ? NSColor.black : NSColor.gray, .paragraphStyle: paragraph]
        let textHeight = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 6, y: (bounds.height - textHeight) / 2, width: bounds.width - 12, height: textHeight), withAttributes: attrs)
    }
}

final class AeroProgress: NSProgressIndicator {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); outline.fill()
        NSColor(calibratedWhite: 0.48, alpha: 1).setStroke(); outline.stroke()
        let fraction = max(0, min(1, doubleValue / max(1, maxValue)))
        if fraction > 0 {
            let fill = NSRect(x: rect.minX + 1, y: rect.minY + 1, width: (rect.width - 2) * fraction, height: rect.height - 2)
            NSGradient(colors: [NSColor(calibratedRed: 0.11, green: 0.62, blue: 0.13, alpha: 1), NSColor(calibratedRed: 0.68, green: 0.95, blue: 0.49, alpha: 1), NSColor(calibratedRed: 0.22, green: 0.77, blue: 0.18, alpha: 1)])?.draw(in: fill, angle: 90)
        }
    }
}
