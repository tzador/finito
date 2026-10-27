import AppKit

enum ConfettiShape: CaseIterable {
    case square, rectangle, triangle, star, circle, hexagon, diamond

    /// Renders the shape filled with `color` into a CGImage of `size` points (rendered at 2x).
    func image(color: NSColor, size: CGFloat) -> CGImage? {
        let scale: CGFloat = 2
        let px = Int(size * scale)
        guard let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path(in: CGRect(x: 0, y: 0, width: size, height: size)))
        ctx.fillPath()
        return ctx.makeImage()
    }

    /// A long thin ribbon with a slightly lighter stripe down the middle.
    static func streamerImage(color: NSColor, width: CGFloat, height: CGFloat) -> CGImage? {
        let scale: CGFloat = 2
        guard let ctx = CGContext(
            data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.28))
        ctx.fill(CGRect(x: width * 0.3, y: 0, width: width * 0.3, height: height))
        return ctx.makeImage()
    }

    /// Soft white glow dot, tinted at runtime for glitter.
    static func glowImage(size: CGFloat) -> CGImage? {
        let scale: CGFloat = 2
        let px = Int(size * scale)
        guard let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.6), CGColor(gray: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 0.35, 1])!
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
        return ctx.makeImage()
    }

    private func path(in rect: CGRect) -> CGPath {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2
        switch self {
        case .square:
            return CGPath(rect: rect.insetBy(dx: r * 0.15, dy: r * 0.15), transform: nil)
        case .rectangle:
            return CGPath(rect: CGRect(x: rect.minX, y: c.y - r * 0.3, width: rect.width, height: r * 0.6), transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect.insetBy(dx: r * 0.1, dy: r * 0.1), transform: nil)
        case .triangle:
            return polygon(center: c, radius: r, sides: 3, startAngle: .pi / 2)
        case .hexagon:
            return polygon(center: c, radius: r, sides: 6, startAngle: 0)
        case .diamond:
            return polygon(center: c, radius: r, sides: 4, startAngle: .pi / 2, squeezeX: 0.6)
        case .star:
            return star(center: c, outer: r, inner: r * 0.45, points: 5)
        }
    }

    private func polygon(center: CGPoint, radius: CGFloat, sides: Int, startAngle: CGFloat, squeezeX: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<sides {
            let angle = startAngle + CGFloat(i) * 2 * .pi / CGFloat(sides)
            let p = CGPoint(x: center.x + radius * cos(angle) * squeezeX, y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private func star(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = .pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
