import AppKit

@MainActor
enum MenuBarIndicatorImageRenderer {
    static let imageSize = NSSize(width: 22, height: 18)
    static let dotRect = NSRect(x: 18, y: 13, width: 4, height: 4)

    static func image(for indicator: MenuBarIndicator) -> NSImage {
        let image = NSImage(size: imageSize, flipped: false) { bounds in
            drawSymbol(named: indicator.symbolName, in: bounds)
            drawBadge(indicator.badge)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSymbol(named name: String, in bounds: NSRect) {
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        ) else {
            return
        }

        let width = min(18, symbol.size.width)
        let height = min(16, symbol.size.height)
        let rect = NSRect(
            x: 0,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        symbol.draw(in: rect)
    }

    private static func drawBadge(_ badge: MenuBarIndicator.Badge) {
        NSColor.black.setFill()

        switch badge {
        case .dot:
            NSBezierPath(ovalIn: dotRect).fill()
        case .pause:
            NSBezierPath(rect: NSRect(x: 16, y: 6, width: 2, height: 6)).fill()
            NSBezierPath(rect: NSRect(x: 20, y: 6, width: 2, height: 6)).fill()
        case .none, .warning:
            break
        }
    }
}
