// Slices the 4x4 leaf sheets in Assets/ into single leaves, strips the background noise,
// packs them into one PNG atlas and writes it as base64 into Sources/Finito/LeafAtlas.swift
// so the binary stays self-contained. Run with scripts/pack-leaves.sh.
import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: pack-leaves <assets dir> <output .swift>\n".data(using: .utf8)!)
    exit(2)
}
let assetsDir = URL(fileURLWithPath: args[1])
let outputPath = args[2]

let cell = 128          // atlas cell size in px
let inner = 120         // max leaf extent inside a cell
let columns = 16
let alphaCut: UInt8 = 80
let grid = 4            // each sheet is grid x grid leaves

struct Bitmap {
    let width: Int, height: Int
    var data: [UInt8]   // premultiplied RGBA, rows bottom-up (CGContext convention)

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        data = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(image: CGImage) {
        self.init(width: image.width, height: image.height)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }

    func cgImage() -> CGImage {
        var copy = data
        return copy.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }
}

/// Returns the leaf in the given region of the sheet as a tightly cropped bitmap, keeping only
/// the largest connected blob of solid pixels (the speckles around the leaves are dropped).
func extractLeaf(from sheet: Bitmap, x0: Int, y0: Int, size: Int) -> Bitmap? {
    var label = [Int32](repeating: 0, count: size * size)
    var best = (id: Int32(0), count: 0)
    var next: Int32 = 1
    var stack: [Int] = []
    for sy in 0..<size {
        for sx in 0..<size where label[sy * size + sx] == 0 && sheet.alpha(x0 + sx, y0 + sy) >= alphaCut {
            let id = next; next += 1
            var count = 0
            stack.append(sy * size + sx); label[sy * size + sx] = id
            while let idx = stack.popLast() {
                count += 1
                let cx = idx % size, cy = idx / size
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]
                where nx >= 0 && ny >= 0 && nx < size && ny < size {
                    let n = ny * size + nx
                    if label[n] == 0 && sheet.alpha(x0 + nx, y0 + ny) >= alphaCut { label[n] = id; stack.append(n) }
                }
            }
            if count > best.count { best = (id, count) }
        }
    }
    guard best.count > 400 else { return nil }

    // Keep the blob plus a one-pixel soft rim so anti-aliased edges survive.
    var keep = [Bool](repeating: false, count: size * size)
    var minX = size, minY = size, maxX = -1, maxY = -1
    for sy in 0..<size {
        for sx in 0..<size {
            let inBlob = label[sy * size + sx] == best.id
            let nearBlob = inBlob
                || (sx > 0 && label[sy * size + sx - 1] == best.id) || (sx < size - 1 && label[sy * size + sx + 1] == best.id)
                || (sy > 0 && label[(sy - 1) * size + sx] == best.id) || (sy < size - 1 && label[(sy + 1) * size + sx] == best.id)
            if nearBlob && sheet.alpha(x0 + sx, y0 + sy) > 0 {
                keep[sy * size + sx] = true
                minX = min(minX, sx); maxX = max(maxX, sx); minY = min(minY, sy); maxY = max(maxY, sy)
            }
        }
    }
    var leaf = Bitmap(width: maxX - minX + 1, height: maxY - minY + 1)
    for sy in minY...maxY {
        for sx in minX...maxX where keep[sy * size + sx] {
            let src = ((y0 + sy) * sheet.width + (x0 + sx)) * 4
            let dst = ((sy - minY) * leaf.width + (sx - minX)) * 4
            for c in 0..<4 { leaf.data[dst + c] = sheet.data[src + c] }
        }
    }
    return leaf
}

let sheets = try FileManager.default.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
var leaves: [Bitmap] = []
for url in sheets {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        FileHandle.standardError.write("skipping unreadable \(url.lastPathComponent)\n".data(using: .utf8)!)
        continue
    }
    let sheet = Bitmap(image: image)
    let size = min(sheet.width, sheet.height) / grid
    var found = 0
    for row in 0..<grid {
        for col in 0..<grid {
            if let leaf = extractLeaf(from: sheet, x0: col * size, y0: row * size, size: size) {
                leaves.append(leaf); found += 1
            }
        }
    }
    print("\(url.lastPathComponent): \(found) leaves")
}
guard !leaves.isEmpty else { FileHandle.standardError.write("no leaves found\n".data(using: .utf8)!); exit(1) }

let rows = (leaves.count + columns - 1) / columns
let atlasWidth = columns * cell, atlasHeight = rows * cell
let ctx = CGContext(data: nil, width: atlasWidth, height: atlasHeight, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
var rects: [Int] = []
for (i, leaf) in leaves.enumerated() {
    let scale = min(CGFloat(inner) / CGFloat(leaf.width), CGFloat(inner) / CGFloat(leaf.height), 1)
    let w = Int((CGFloat(leaf.width) * scale).rounded()), h = Int((CGFloat(leaf.height) * scale).rounded())
    let x = (i % columns) * cell + (cell - w) / 2
    let y = (i / columns) * cell + (cell - h) / 2
    ctx.draw(leaf.cgImage(), in: CGRect(x: x, y: y, width: w, height: h))
    rects += [x, y, w, h]
}

let atlas = ctx.makeImage()!
let pngData = NSMutableData()
let dest = CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, atlas, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
let base64 = (pngData as Data).base64EncodedString()

var swift = """
// Generated by scripts/pack-leaves.sh from the sheets in Assets/. Do not edit by hand.
//
// One PNG atlas of \(leaves.count) autumn leaves, embedded so the binary needs no resource bundle.

enum LeafAtlas {
    static let width = \(atlasWidth)
    static let height = \(atlasHeight)
    /// Flat [x, y, w, h] quadruples in atlas pixels, origin bottom-left (SpriteKit's unit space).
    static let rects: [Int] = [

"""
for i in stride(from: 0, to: rects.count, by: 16) {
    swift += "        " + rects[i..<min(i + 16, rects.count)].map(String.init).joined(separator: ", ") + ",\n"
}
swift += "    ]\n\n    static let png = \"\(base64)\"\n}\n"
try swift.write(toFile: outputPath, atomically: true, encoding: .utf8)
print("atlas \(atlasWidth)x\(atlasHeight), \(leaves.count) leaves, png \(pngData.length / 1024) KB -> \(outputPath)")
