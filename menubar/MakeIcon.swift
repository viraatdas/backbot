// Renders BackbotMark into an .iconset directory. build.sh runs this and then
// hands the directory to `iconutil` to produce AppIcon.icns.
//
// Usage: makeicon <output.iconset>

import Cocoa

@main
struct MakeIcon {
    // (point size, scale) -> the filenames iconutil expects.
    static let variants: [(pt: Int, scale: Int)] = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            fail("usage: makeicon <output.iconset> [--shape fullbleed|rounded]", 2)
        }

        // macOS 26 masks and shadows full-bleed art itself; 13-15 draw the icns
        // as-is and need us to supply the rounded shape. build.sh picks.
        var shape: BackbotIconShape = .fullBleed
        if let i = args.firstIndex(of: "--shape"), i + 1 < args.count {
            switch args[i + 1] {
            case "rounded":   shape = .rounded
            case "fullbleed": shape = .fullBleed
            default: fail("unknown shape: \(args[i + 1])", 2)
            }
        }

        let outDir = URL(fileURLWithPath: args[1])
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for v in variants {
            let px = v.pt * v.scale
            guard let cg = BackbotMark.appIcon(px: px, shape: shape) else {
                fail("failed to render \(px)px")
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: px, height: px)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                fail("failed to encode \(px)px")
            }
            let name = v.scale == 1 ? "icon_\(v.pt)x\(v.pt).png"
                                    : "icon_\(v.pt)x\(v.pt)@2x.png"
            try png.write(to: outDir.appendingPathComponent(name))
        }

        print("wrote \(variants.count) images to \(outDir.path)")
    }

    static func fail(_ msg: String, _ code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
        exit(code)
    }
}
