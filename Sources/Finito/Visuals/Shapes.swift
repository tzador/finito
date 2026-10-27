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
