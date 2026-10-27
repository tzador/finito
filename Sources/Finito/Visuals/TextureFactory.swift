import AppKit
import SpriteKit

/// Rasterizes textures at 2x with Core Graphics so the effects need no image assets.
enum TextureFactory {
    static func make(size: CGSize, scale: CGFloat = 2, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        let px = (Int(size.width * scale), Int(size.height * scale))
        let ctx = CGContext(
            data: nil, width: px.0, height: px.1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx, CGRect(origin: .zero, size: size))
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }

    static func make(size: CGFloat, scale: CGFloat = 2, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        make(size: CGSize(width: size, height: size), scale: scale, draw: draw)
    }

    /// White filled path, meant to be tinted with `SKSpriteNode.color`.
    static func shape(size: CGFloat, path: (CGRect) -> CGPath) -> SKTexture {
        make(size: size) { ctx, rect in
            ctx.setFillColor(.white)
            ctx.addPath(path(rect))
            ctx.fillPath()
        }
    }

    /// Soft radial glow: opaque white centre fading to transparent at the edge.
    static func glow(size: CGFloat, hardness: CGFloat = 0.0) -> SKTexture {
        make(size: size) { ctx, rect in
            let colors = [
                CGColor(gray: 1, alpha: 1),
                CGColor(gray: 1, alpha: 1),
                CGColor(gray: 1, alpha: 0.35),
                CGColor(gray: 1, alpha: 0),
            ] as CFArray
            let locations: [CGFloat] = [0, hardness * 0.8, 0.45 + hardness * 0.3, 1]
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: locations)!
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width / 2, options: [])
        }
    }

    /// Four-point sparkle with thin rays over a faint glow.
    static func sparkle(size: CGFloat) -> SKTexture {
        make(size: size) { ctx, rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2
            let colors = [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 0.5, options: [])
            ctx.setFillColor(.white)
            ctx.addPath(Paths.star(center: c, outer: r, inner: r * 0.09, points: 4, startAngle: .pi / 2))
            ctx.fillPath()
        }
    }

    /// Horizontal beam: bright core line fading toward both edges and toward the far end.
    static func beam(length: CGFloat, thickness: CGFloat) -> SKTexture {
        make(size: CGSize(width: length, height: thickness), scale: 1) { ctx, rect in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let across = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0),
            ] as CFArray, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(across, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: rect.height), options: [])
            ctx.setBlendMode(.destinationIn)
            let along = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0),
            ] as CFArray, locations: [0, 0.55, 1])!
            ctx.drawLinearGradient(along, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: 0), options: [])
        }
    }

    /// Thin ring with soft inner and outer edges.
    static func ring(size: CGFloat, thickness: CGFloat) -> SKTexture {
        make(size: size) { ctx, rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2
            let t = thickness / rect.width
            let colors = [
                CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0),
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [1 - t * 2, 1 - t, 1])!
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
    }

    /// Text glyph rendered in white, for tinting.
    static func glyph(_ text: String, size: CGFloat, font: NSFont) -> SKTexture {
        make(size: size) { ctx, rect in
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            defer { NSGraphicsContext.current = previous }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let string = NSAttributedString(string: text, attributes: attributes)
            let bounds = string.size()
            string.draw(at: CGPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
        }
    }
}

enum Paths {
    static func polygon(center: CGPoint, radius: CGFloat, sides: Int, startAngle: CGFloat, squeezeX: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<sides {
            let angle = startAngle + CGFloat(i) * 2 * .pi / CGFloat(sides)
            let p = CGPoint(x: center.x + radius * cos(angle) * squeezeX, y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func star(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, startAngle: CGFloat = .pi / 2) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = startAngle + CGFloat(i) * .pi / CGFloat(points)
            let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func heart(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        path.move(to: CGPoint(x: x + w / 2, y: y + h * 0.12))
        path.addCurve(to: CGPoint(x: x + w * 0.02, y: y + h * 0.68),
                      control1: CGPoint(x: x + w * 0.3, y: y - h * 0.05),
                      control2: CGPoint(x: x - w * 0.08, y: y + h * 0.38))
        path.addArc(center: CGPoint(x: x + w * 0.27, y: y + h * 0.7), radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addArc(center: CGPoint(x: x + w * 0.73, y: y + h * 0.7), radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: CGPoint(x: x + w / 2, y: y + h * 0.12),
                      control1: CGPoint(x: x + w * 1.08, y: y + h * 0.38),
                      control2: CGPoint(x: x + w * 0.7, y: y - h * 0.05))
        path.closeSubpath()
        return path
    }
}
