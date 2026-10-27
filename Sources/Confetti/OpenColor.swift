import AppKit

/// Mid-range (shade 5 and 6) colors from the Open Color palette (https://yeun.github.io/open-color/).
enum OpenColor {
    static let mid: [NSColor] = [
        // shade 5
        "#ff6b6b", "#f06595", "#cc5de8", "#845ef7", "#5c7cfa", "#339af0",
        "#22b8cf", "#20c997", "#51cf66", "#94d82d", "#fcc419", "#ff922b",
        // shade 6
        "#fa5252", "#e64980", "#be4bdb", "#7950f2", "#4c6ef5", "#228be6",
        "#15aabf", "#12b886", "#40c057", "#82c91e", "#fab005", "#fd7e14",
    ].map(NSColor.fromHex)
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
