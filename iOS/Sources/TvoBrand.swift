import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TvoMascotIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x62D9FF), Color(hex: 0x3978F6), Color(hex: 0x6553DF)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: size * 0.82, height: size * 0.82)

                TvoBlueberry()
                    .frame(width: size * 0.72, height: size * 0.72)
                    .shadow(color: Color(hex: 0x172A69).opacity(0.28), radius: size * 0.035, y: size * 0.025)

                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.11, weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: size * 0.82, y: size * 0.22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel("Tvo, a cute blue blueberry")
    }
}

/// A cute blue blueberry mascot.
struct TvoBlueberry: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                // berry body
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: Palette.berry1), Color(hex: Palette.berry2),
                                     Color(hex: Palette.berry3), Color(hex: Palette.berry4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.86, height: size * 1.0)
                    .offset(y: size * 0.10)

                // shine
                Ellipse()
                    .fill(.white.opacity(0.4))
                    .frame(width: size * 0.44, height: size * 0.3)
                    .offset(x: -size * 0.15, y: -size * 0.2)

                // outline
                Ellipse()
                    .stroke(Color(hex: Palette.nose), lineWidth: size * 0.02)
                    .frame(width: size * 0.86, height: size * 1.0)
                    .offset(y: size * 0.10)

                // leaves
                HStack(spacing: size * 0.14) {
                    TvoBerryLeaf(rotation: -20)
                    TvoBerryLeaf(rotation: 10)
                }
                .position(x: size * 0.5, y: size * 0.14)

                // eyes
                HStack(spacing: size * 0.28) {
                    berryEye(side: -1, size: size)
                    berryEye(side: 1, size: size)
                }
                .position(x: size * 0.5, y: size * 0.44)

                // blush
                HStack(spacing: size * 0.52) {
                    berryBlush(side: -1, size: size)
                    berryBlush(side: 1, size: size)
                }
                .position(x: size * 0.5, y: size * 0.60)

                // smile
                Path { p in
                    p.move(to: CGPoint(x: size * 0.37, y: size * 0.66))
                    p.addQuadCurve(to: CGPoint(x: size * 0.63, y: size * 0.66),
                                   control: CGPoint(x: size * 0.5, y: size * 0.80))
                }
                .stroke(Color(hex: Palette.nose), style: StrokeStyle(lineWidth: size * 0.03, lineCap: CGLineCap.round, lineJoin: CGLineJoin.round))
                .position(x: size * 0.5, y: size * 0.5)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel("Tvo, a cute blue blueberry")
    }

    private func berryEye(side: CGFloat, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: Palette.nose))
                .frame(width: size * 0.115, height: size * 0.14)
            Circle()
                .fill(.white)
                .frame(width: size * 0.045, height: size * 0.045)
                .offset(x: -size * 0.025, y: -size * 0.02)
        }
    }

    private func berryBlush(side: CGFloat, size: CGFloat) -> some View {
        Ellipse()
            .fill(.white.opacity(0.32))
            .frame(width: size * 0.17, height: size * 0.10)
            .blur(radius: size * 0.025)
    }
}

/// One little leaf on the blueberry's crown.
private struct TvoBerryLeaf: View {
    let rotation: Double
    var body: some View {
        ZStack {
            leafPath.fill(Color(hex: Palette.berry3))
            leafPath.stroke(Color(hex: Palette.nose), style: StrokeStyle(lineWidth: 2.5, lineCap: CGLineCap.round, lineJoin: CGLineJoin.round))
        }
        .rotationEffect(.degrees(rotation))
    }

    private var leafPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addQuadCurve(to: CGPoint(x: 14, y: -42), control: CGPoint(x: 6, y: -14))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -6, y: -14))
        }
    }
}

// MARK: - Dot animation forming "TVO"

/// Dots scatter across the screen, then converge to form the letters "TVO", then idle.
struct TvoDotLogo: View {
    @State private var dots: [Dot] = []
    @State private var startTime: Double = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let animTime = timeline.date.timeIntervalSinceReferenceDate - startTime
                Canvas { ctx, size in
                    for dot in dots {
                        let pos = dot.position(at: animTime, size: size)
                        let r = dot.r
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: pos.x - r / 2, y: pos.y - r / 2, width: r, height: r)),
                            with: .color(dot.color)
                        )
                    }
                }
            }
            .onAppear {
                startTime = Date().timeIntervalSinceReferenceDate
                dots = Self.makeDots(in: geometry.size)
            }
        }
    }

    // MARK: - Dot model

    private struct Dot {
        let target: CGPoint
        let home: CGPoint
        let color: Color
        let r: CGFloat

        func position(at t: Double, size: CGSize) -> CGPoint {
            let scatterUntil = 2.0
            let formUntil = 4.5
            if t < scatterUntil {
                // drift around home (dots all over the screen)
                return CGPoint(
                    x: home.x + sin(t * 1.5 + Double(target.x).truncatingRemainder(dividingBy: 7)) * 18,
                    y: home.y + cos(t * 1.1 + Double(target.y).truncatingRemainder(dividingBy: 7)) * 18
                )
            } else if t < formUntil {
                // converge to the text
                    let p = TvoDotLogo.easeOutCubic((t - scatterUntil) / (formUntil - scatterUntil))
                return CGPoint(
                    x: home.x + (target.x - home.x) * p,
                    y: home.y + (target.y - home.y) * p
                )
            } else {
                // idle wobble around the letter
                return CGPoint(
                    x: target.x + sin(t * 2.0 + Double(target.x).truncatingRemainder(dividingBy: 5)) * 5,
                    y: target.y + cos(t * 1.6 + Double(target.y).truncatingRemainder(dividingBy: 5)) * 5
                )
            }
        }
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private static func makeDots(in size: CGSize) -> [Dot] {
        let targets = samplePoints("TVO", in: size)
        guard !targets.isEmpty else { return [] }
        let count = min(max(targets.count * 2, 900), 2000)
        let colors: [Color] = [
            Color(hex: Palette.berry1), Color(hex: Palette.berry2),
            Color(hex: Palette.berry3), Color(hex: Palette.berry4),
            Color(hex: Palette.inkSoft),
        ]
        var dots: [Dot] = []
        for i in 0..<count {
            let target = targets[i % targets.count]
            let h = Double(i)
            let home = CGPoint(
                x: size.width * 0.1 + CGFloat(sin(h * 0.37)) * size.width * 0.8
                    + CGFloat(cos(h * 0.21)) * 60,
                y: size.height * 0.1 + CGFloat(cos(h * 0.29)) * size.height * 0.8
                    + CGFloat(sin(h * 0.41)) * 60
            )
            dots.append(Dot(
                target: target,
                home: home,
                color: colors[Int(h.truncatingRemainder(dividingBy: Double(colors.count))) % colors.count],
                r: 1.4 + CGFloat(h.truncatingRemainder(dividingBy: 4)) * 0.7
            ))
        }
        return dots
    }

    /// Render the text to an image and sample alpha pixels as dot targets.
    private static func samplePoints(_ text: String, in size: CGSize) -> [CGPoint] {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor.white.set()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let fontSize = min(size.width, size.height) * 0.20
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(in: CGRect(origin: .zero, size: size), withAttributes: attrs)
        }
        let cg = img.cgImage
        let width = cg?.width ?? 0
        let height = cg?.height ?? 0
        guard width > 0, height > 0 else { return [] }
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        pixelData.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            guard let context = CGContext(data: baseAddress, width: width, height: height,
                                          bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)) else { return }
            context.draw(cg!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let scaleX = CGFloat(width) / size.width
        let scaleY = CGFloat(height) / size.height
        let sampleStride = 6
        var points: [CGPoint] = []
        for y in stride(from: 0, to: height, by: sampleStride) {
            for x in stride(from: 0, to: width, by: sampleStride) {
                let i = (y * width + x) * bytesPerPixel
                if pixelData[i + 3] > 100 {
                    points.append(CGPoint(x: CGFloat(x) / scaleX, y: CGFloat(y) / scaleY))
                }
            }
        }
        return points
        #else
        return []
        #endif
    }
}

// MARK: - Existing wordmark (kept)

struct TvoWordmark: View {
    var progress: CGFloat = 1
    var dotOpacity: Double = 0

    private let letters: [(Character, CGFloat)] = [
        ("T", 0.78), ("V", 0.92), ("O", 0.92), ("G", 0.96)
    ]

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let stroke = height * 0.19
            HStack(spacing: height * -0.035) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, item in
                    let width = height * item.1
                    ZStack {
                        LogoGlyph(character: item.0, stroke: stroke)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x59DFFF), Color(hex: 0x7F8CFF), Color(hex: 0xBF76FF)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .scaleEffect(max(0.04, progress), anchor: .center)
                            .opacity(Double(progress))

                        Circle()
                            .fill(Color(hex: 0x65DFFF))
                            .frame(width: height * 0.18, height: height * 0.18)
                            .scaleEffect(1 - progress * 0.82)
                            .opacity(dotOpacity)
                            .shadow(color: Color(hex: 0x65DFFF).opacity(dotOpacity * 0.8), radius: height * 0.12)
                    }
                    .frame(width: width, height: height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel("TVOG")
    }
}

private struct LogoGlyph: Shape {
    let character: Character
    let stroke: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = stroke / 2
        var path = Path()

        switch character {
        case "T":
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        case "V":
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        case "O":
            path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset),
                                cornerSize: CGSize(width: rect.width * 0.22, height: rect.width * 0.22))
        case "G":
            path.move(to: CGPoint(x: rect.maxX - inset * 1.2, y: rect.minY + rect.height * 0.25))
            path.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.minY + inset),
                          control1: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + inset),
                          control2: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.minY + inset))
            path.addCurve(to: CGPoint(x: rect.minX + inset, y: rect.midY),
                          control1: CGPoint(x: rect.minX + inset, y: rect.minY + inset),
                          control2: CGPoint(x: rect.minX + inset, y: rect.minY + rect.height * 0.3))
            path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY - inset),
                          control1: CGPoint(x: rect.minX + inset, y: rect.maxY - rect.height * 0.2),
                          control2: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY - inset))
            path.addCurve(to: CGPoint(x: rect.maxX - inset, y: rect.midY + rect.height * 0.05),
                          control1: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - inset),
                          control2: CGPoint(x: rect.maxX - inset, y: rect.maxY - rect.height * 0.15))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.05))
        default:
            break
        }
        return path.strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .square, lineJoin: .round))
    }
}
