// BackbotMark — the backbot logo, drawn in Core Graphics.
//
// One vector definition feeds both the menu bar glyph and the app icon, so the
// thing you see in the menu bar and the thing you see in System Settings ›
// Login Items are the same mark. Generated at build time; no binary art in the
// repo.
//
// The mark: a minimal bot head — rounded square, two eyes, an antenna capped
// with the same dot the website uses as its brand mark. Status is carried by an
// SF-Symbols-style badge knocked out of the bottom-right corner.

import Cocoa

enum BackbotBadge {
    case none
    case ok
    case failed
    case running(phase: CGFloat)   // 0..1, spins the arc
}

/// How the app icon's tile is produced.
enum BackbotIconShape {
    /// Opaque, edge to edge. macOS 26 rounds and shadows app icons itself, but
    /// only for art that fills its canvas; this is what makes the icon sit
    /// level with Terminal.app and Arc there. Older systems do no masking, so
    /// this variant would ship them a hard square.
    case fullBleed
    /// The classic 824-in-1024 squircle with a baked shadow, which is what
    /// macOS 13-15 expect since they draw the icns as-is.
    case rounded
}

enum BackbotMark {

    // MARK: - Design space
    //
    // Everything below is expressed in a 100x100, y-up design space and scaled
    // by the caller. The bare mark occupies x[14.5, 85.5], y[8.5, 92]; a badge
    // extends the drawn area to the bottom-right corner (100, 0).

    static let canvas: CGFloat = 100

    private static let head = CGRect(x: 18, y: 12, width: 64, height: 58)
    private static let headRadius: CGFloat = 19
    private static let antennaTop = CGPoint(x: 50, y: 80.5)
    private static let antennaDot = CGPoint(x: 50, y: 86)
    private static let antennaDotR: CGFloat = 6
    private static let eyeR: CGFloat = 6
    private static let eyeY: CGFloat = 41
    private static let eyeDX: CGFloat = 12.5

    // Pushed well into the corner: any closer in and the knockout eats the
    // head's whole bottom edge instead of just clipping its corner.
    private static let badgeCenter = CGPoint(x: 84, y: 16)
    private static let badgeClearR: CGFloat = 20.5   // knockout radius
    private static let badgeArcR: CGFloat = 11.5

    // MARK: - Core drawing

    /// Draws the mark into `rect`, mapping the 100x100 design space onto it.
    /// `stroke` is a line width in design-space units.
    ///
    /// `filled` swaps the outlined head for a solid silhouette with the eyes
    /// knocked out. Below roughly 20px an outlined head is thinner than a
    /// pixel and turns to mush, so the small icon variants use the solid form.
    static func draw(in ctx: CGContext,
                     rect: CGRect,
                     badge: BackbotBadge = .none,
                     stroke: CGFloat = 7,
                     filled: Bool = false,
                     color: CGColor = NSColor.black.cgColor) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / canvas, y: rect.height / canvas)

        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(stroke)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Antenna + its dot (the same dot the site uses as its brand mark)
        ctx.move(to: CGPoint(x: head.midX, y: head.maxY))
        ctx.addLine(to: antennaTop)
        ctx.strokePath()
        ctx.fillEllipse(in: circle(antennaDot, antennaDotR))

        // Head
        let headPath = CGPath(roundedRect: head,
                              cornerWidth: headRadius, cornerHeight: headRadius,
                              transform: nil)
        ctx.addPath(headPath)
        if filled { ctx.fillPath() } else { ctx.strokePath() }

        // Eyes: drawn on top of a solid head means punching them back out.
        let eyes = [CGPoint(x: head.midX - eyeDX, y: eyeY),
                    CGPoint(x: head.midX + eyeDX, y: eyeY)]
        ctx.saveGState()
        if filled { ctx.setBlendMode(.clear) }
        for e in eyes { ctx.fillEllipse(in: circle(e, eyeR)) }
        ctx.restoreGState()

        // Badge: punch a clear ring out of the head, then draw the glyph in it.
        if !isNone(badge) {
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: circle(badgeCenter, badgeClearR))
            ctx.restoreGState()

            ctx.setLineWidth(stroke)
            switch badge {
            case .none:
                break
            case .ok:
                ctx.move(to: CGPoint(x: 75, y: 16.9))
                ctx.addLine(to: CGPoint(x: 81.3, y: 9.7))
                ctx.addLine(to: CGPoint(x: 93.9, y: 24.1))
                ctx.strokePath()
            case .failed:
                ctx.move(to: CGPoint(x: 76, y: 8))
                ctx.addLine(to: CGPoint(x: 92, y: 24))
                ctx.move(to: CGPoint(x: 76, y: 24))
                ctx.addLine(to: CGPoint(x: 92, y: 8))
                ctx.strokePath()
            case .running(let phase):
                // A three-quarter arc; rotating it is what reads as "busy" at
                // menu bar size, where the arrowhead shape itself would not.
                let start = -phase * 2 * .pi
                ctx.addArc(center: badgeCenter, radius: badgeArcR,
                           startAngle: start, endAngle: start - 1.5 * .pi,
                           clockwise: true)
                ctx.strokePath()
            }
        }

        ctx.restoreGState()
    }

    // MARK: - Rendering

    /// The mark on its own transparent layer. Both the eye and badge knockouts
    /// clear pixels, so the mark has to be composited rather than drawn
    /// straight onto a background it would otherwise punch a hole through.
    static func markImage(px: Int,
                          badge: BackbotBadge = .none,
                          stroke: CGFloat = 7,
                          filled: Bool = false,
                          color: CGColor = NSColor.black.cgColor) -> CGImage? {
        guard px > 0, let ctx = bitmap(px: px, py: px) else { return nil }
        draw(in: ctx,
             rect: CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)),
             badge: badge, stroke: stroke, filled: filled, color: color)
        return ctx.makeImage()
    }

    /// A template NSImage for NSStatusItem. Rendered oversampled so it stays
    /// crisp on any display scale.
    static func statusImage(pointSize: CGFloat = 18,
                            badge: BackbotBadge = .none) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let px = Int((pointSize * 4).rounded())
        guard let cg = markImage(px: px, badge: badge) else { return NSImage(size: size) }
        let img = NSImage(cgImage: cg, size: size)
        img.isTemplate = true
        return img
    }

    // MARK: - App icon

    /// One square of the app icon at `px` x `px`. Near-black tile, white mark:
    /// the site is black-on-white, so the icon inverts it — and unlike a white
    /// icon it still reads on a light Finder or Login Items row.
    ///
    /// `shape` picks who draws the tile — see BackbotIconShape. build.sh
    /// chooses based on the macOS version doing the building.
    static func appIcon(px: Int, shape: BackbotIconShape = .fullBleed) -> CGImage? {
        guard px > 0, let ctx = bitmap(px: px, py: px) else { return nil }
        let s = CGFloat(px) / 1024
        let detailed = px >= 64          // the sheen is mush below this

        let content: CGRect
        var clip: CGPath? = nil
        switch shape {
        case .fullBleed:
            content = CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
        case .rounded:
            content = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
            clip = squircle(in: content)
        }

        // Baked shadow, only where the system will not supply one.
        if let shapePath = clip, detailed {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12 * s),
                          blur: 28 * s,
                          color: NSColor(white: 0, alpha: 0.22).cgColor)
            ctx.addPath(shapePath)
            ctx.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        if let shapePath = clip { ctx.addPath(shapePath); ctx.clip() }

        // Body gradient
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [rgb(0.16, 0.16, 0.18), rgb(0.04, 0.04, 0.05)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: content.midX, y: content.maxY),
                                   end: CGPoint(x: content.midX, y: content.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // Sheen: a soft pool of light spilling in from above the top edge.
        if detailed,
           let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [white(0.10), white(0)] as CFArray,
                                  locations: [0, 1]) {
            ctx.drawRadialGradient(sheen,
                                   startCenter: CGPoint(x: content.midX, y: content.maxY),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: content.midX, y: content.maxY),
                                   endRadius: content.width * 0.85,
                                   options: [])
        }
        ctx.restoreGState()

        // The mark, ~60% of the tile (a touch larger and solid when the square
        // is too small to hold an outline). Composited from its own layer so
        // the knocked-out eyes read as dark, not as holes.
        let tiny = px <= 20
        let box = Int((content.width * (tiny ? 0.70 : 0.60)).rounded())
        if let mark = markImage(px: box,
                                badge: .none,
                                stroke: detailed ? 6.4 : 9,
                                filled: tiny,
                                color: white(1)) {
            let o = (CGFloat(px) - CGFloat(box)) / 2
            ctx.draw(mark, in: CGRect(x: o, y: o, width: CGFloat(box), height: CGFloat(box)))
        }

        return ctx.makeImage()
    }

    // MARK: - Helpers

    private static func bitmap(px: Int, py: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: px, height: py,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.setAllowsAntialiasing(true)
        ctx?.setShouldAntialias(true)
        ctx?.interpolationQuality = .high
        return ctx
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func white(_ a: CGFloat) -> CGColor {
        CGColor(red: 1, green: 1, blue: 1, alpha: a)
    }

    private static func isNone(_ b: BackbotBadge) -> Bool {
        if case .none = b { return true }
        return false
    }

    /// The macOS app icon shape: straight sides with continuous ("squircle")
    /// corners. Each corner is a quarter superellipse; a plain rounded rect
    /// reads visibly wrong next to system icons, and a full superellipse bows
    /// the sides out into a blob.
    private static func squircle(in rect: CGRect, n: Double = 5) -> CGPath {
        let r = min(rect.width, rect.height) * 0.225   // Apple's ratio
        let path = CGMutablePath()
        let e = 2 / n
        let steps = 48

        // Corner centers, walked counter-clockwise from the right edge so the
        // straight sides fall out of the arc endpoints.
        let corners = [
            (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0.0),              // top-right
            (CGPoint(x: rect.minX + r, y: rect.maxY - r), Double.pi / 2),    // top-left
            (CGPoint(x: rect.minX + r, y: rect.minY + r), Double.pi),        // bottom-left
            (CGPoint(x: rect.maxX - r, y: rect.minY + r), 3 * Double.pi / 2) // bottom-right
        ]

        for (i, corner) in corners.enumerated() {
            let (c, base) = corner
            for j in 0...steps {
                let t = base + Double(j) / Double(steps) * (Double.pi / 2)
                let ct = cos(t), st = sin(t)
                let p = CGPoint(x: c.x + r * CGFloat((ct < 0 ? -1.0 : 1.0) * pow(abs(ct), e)),
                                y: c.y + r * CGFloat((st < 0 ? -1.0 : 1.0) * pow(abs(st), e)))
                if i == 0 && j == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        path.closeSubpath()
        return path
    }
}
