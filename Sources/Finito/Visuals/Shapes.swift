import AppKit

enum ConfettiShape: CaseIterable {
    case square, rectangle, triangle, star, circle, hexagon, diamond

    func path(in rect: CGRect) -> CGPath {
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
            return Paths.polygon(center: c, radius: r, sides: 3, startAngle: .pi / 2)
        case .hexagon:
            return Paths.polygon(center: c, radius: r, sides: 6, startAngle: 0)
        case .diamond:
            return Paths.polygon(center: c, radius: r, sides: 4, startAngle: .pi / 2, squeezeX: 0.6)
        case .star:
            return Paths.star(center: c, outer: r, inner: r * 0.45, points: 5)
        }
    }
}
