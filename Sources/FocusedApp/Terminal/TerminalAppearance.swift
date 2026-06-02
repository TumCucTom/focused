import AppKit
import SwiftTerm

/// Visual styling that matches macOS Terminal.app's built-in "Basic" (light)
/// and "Pro" (dark) themes. Colors are taken from the .terminal files shipped
/// with Terminal.app.
struct TerminalAppearance {
    let font: NSFont
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let selectionColor: NSColor
    let cursorColor: NSColor
    let palette: [Color]

    nonisolated(unsafe) static let basic = TerminalAppearance(
        fontSize: 11,
        background: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        foreground: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        selection: NSColor(srgbRed: 0.80, green: 0.87, blue: 0.93, alpha: 0.7),
        cursor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        palette: basicPalette()
    )

    nonisolated(unsafe) static let pro = TerminalAppearance(
        fontSize: 11,
        background: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        foreground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        selection: NSColor(srgbRed: 0.30, green: 0.46, blue: 0.77, alpha: 0.6),
        cursor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        palette: proPalette()
    )

    private init(
        fontSize: CGFloat,
        background: NSColor,
        foreground: NSColor,
        selection: NSColor,
        cursor: NSColor,
        palette: [Color]
    ) {
        self.font = TerminalAppearance.resolveFont(size: fontSize)
        self.backgroundColor = background
        self.foregroundColor = foreground
        self.selectionColor = selection
        self.cursorColor = cursor
        self.palette = palette
    }

    static func resolveFont(size: CGFloat) -> NSFont {
        let candidates = ["SFMono-Regular", "SF Mono", "Menlo-Regular", "Menlo"]
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // 16 ANSI colors: 0..7 normal, 8..15 bright.
    private static func basicPalette() -> [Color] {
        return [
            // Normal
            Color(red: 0, green: 0, blue: 0),
            Color(red: 194/255, green: 54/255, blue: 33/255),
            Color(red: 37/255, green: 188/255, blue: 36/255),
            Color(red: 173/255, green: 173/255, blue: 39/255),
            Color(red: 73/255, green: 46/255, blue: 225/255),
            Color(red: 211/255, green: 56/255, blue: 211/255),
            Color(red: 51/255, green: 187/255, blue: 200/255),
            Color(red: 203/255, green: 204/255, blue: 205/255),
            // Bright
            Color(red: 129/255, green: 131/255, blue: 132/255),
            Color(red: 252/255, green: 57/255, blue: 31/255),
            Color(red: 49/255, green: 231/255, blue: 34/255),
            Color(red: 234/255, green: 236/255, blue: 35/255),
            Color(red: 88/255, green: 51/255, blue: 255/255),
            Color(red: 255/255, green: 0, blue: 255/255),
            Color(red: 20/255, green: 240/255, blue: 240/255),
            Color(red: 255/255, green: 255/255, blue: 255/255),
        ]
    }

    private static func proPalette() -> [Color] {
        return [
            // Normal
            Color(red: 0, green: 0, blue: 0),
            Color(red: 194/255, green: 54/255, blue: 33/255),
            Color(red: 37/255, green: 188/255, blue: 36/255),
            Color(red: 173/255, green: 173/255, blue: 39/255),
            Color(red: 73/255, green: 46/255, blue: 225/255),
            Color(red: 211/255, green: 56/255, blue: 211/255),
            Color(red: 51/255, green: 187/255, blue: 200/255),
            Color(red: 203/255, green: 204/255, blue: 205/255),
            // Bright
            Color(red: 129/255, green: 131/255, blue: 132/255),
            Color(red: 252/255, green: 57/255, blue: 31/255),
            Color(red: 49/255, green: 231/255, blue: 34/255),
            Color(red: 234/255, green: 236/255, blue: 35/255),
            Color(red: 88/255, green: 51/255, blue: 255/255),
            Color(red: 255/255, green: 0, blue: 255/255),
            Color(red: 20/255, green: 240/255, blue: 240/255),
            Color(red: 255/255, green: 255/255, blue: 255/255),
        ]
    }
}

extension LocalProcessTerminalView {
    func apply(appearance: TerminalAppearance) {
        font = appearance.font
        nativeBackgroundColor = appearance.backgroundColor
        nativeForegroundColor = appearance.foregroundColor
        installColors(appearance.palette)
        layer?.backgroundColor = appearance.backgroundColor.cgColor
    }
}
