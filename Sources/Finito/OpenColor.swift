import AppKit

/// Colors from the Open Color palette (https://yeun.github.io/open-color/).
enum OpenColor {
    /// Mid-range (shade 5 and 6) colors across the whole hue wheel.
    static let mid: [NSColor] = [
        // shade 5
        "#ff6b6b", "#f06595", "#cc5de8", "#845ef7", "#5c7cfa", "#339af0",
        "#22b8cf", "#20c997", "#51cf66", "#94d82d", "#fcc419", "#ff922b",
        // shade 6
        "#fa5252", "#e64980", "#be4bdb", "#7950f2", "#4c6ef5", "#228be6",
        "#15aabf", "#12b886", "#40c057", "#82c91e", "#fab005", "#fd7e14",
    ].map(NSColor.fromHex)

    /// Shade 3: soft pastels.
    static let pastel: [NSColor] = [
        "#ffa8a8", "#faa2c1", "#e599f7", "#b197fc", "#91a7ff", "#74c0fc",
        "#66d9e8", "#63e6be", "#8ce99a", "#c0eb75", "#ffe066", "#ffc078",
    ].map(NSColor.fromHex)

    static let warm: [NSColor] = [
        "#ff6b6b", "#fa5252", "#f06595", "#e64980", "#ff922b", "#fd7e14", "#fcc419", "#fab005", "#ffd43b", "#ff8787",
    ].map(NSColor.fromHex)

    static let cool: [NSColor] = [
        "#339af0", "#228be6", "#22b8cf", "#15aabf", "#20c997", "#12b886", "#5c7cfa", "#4c6ef5", "#845ef7", "#7950f2", "#74c0fc",
    ].map(NSColor.fromHex)

    static let gold: [NSColor] = [
        "#ffd43b", "#fcc419", "#fab005", "#f59f00", "#fff3bf", "#ffffff", "#e9ecef", "#ced4da", "#ffe066",
    ].map(NSColor.fromHex)

    static let party: [NSColor] = [
        "#f06595", "#e64980", "#cc5de8", "#be4bdb", "#22b8cf", "#3bc9db", "#fcc419", "#ffd43b", "#ffffff",
    ].map(NSColor.fromHex)

    static let themes: [[NSColor]] = [mid, mid, pastel, warm, cool, gold, party]
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
