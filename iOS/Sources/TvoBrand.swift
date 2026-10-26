import SwiftUI

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

                TvoDogHead()
                    .frame(width: size * 0.72, height: size * 0.72)
                    .shadow(color: Color(hex: 0x172A69).opacity(0.28), radius: size * 0.035, y: size * 0.025)

                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.11, weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: size * 0.82, y: size * 0.22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel("Tvo, a friendly blue dog")
    }
}

private struct TvoDogHead: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                HStack(spacing: size * 0.25) {
                    Capsule()
                        .fill(Color(hex: 0x58A9F8))
                        .frame(width: size * 0.25, height: size * 0.52)
                        .rotationEffect(.degrees(-22))
                    Capsule()
                        .fill(Color(hex: 0x58A9F8))
                        .frame(width: size * 0.25, height: size * 0.52)
                        .rotationEffect(.degrees(22))
                }
                .offset(y: -size * 0.12)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xBDEFFF), Color(hex: 0x66C8FF), Color(hex: 0x4B8AFF)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.86, height: size * 0.78)
                    .overlay {
                        Ellipse()
                            .stroke(Color.white.opacity(0.65), lineWidth: size * 0.018)
                    }
                    .offset(y: size * 0.07)

                HStack(spacing: size * 0.13) {
                    eye(size: size)
                    eye(size: size)
                }
                .position(x: size * 0.5, y: size * 0.45)

                Ellipse()
                    .fill(Color(hex: 0xDDF7FF))
                    .frame(width: size * 0.4, height: size * 0.23)
                    .position(x: size * 0.5, y: size * 0.66)

                Ellipse()
                    .fill(Color(hex: 0x25345F))
                    .frame(width: size * 0.105, height: size * 0.07)
                    .position(x: size * 0.5, y: size * 0.59)

                SmileShape()
                    .stroke(Color(hex: 0x25345F), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                    .frame(width: size * 0.16, height: size * 0.08)
                    .position(x: size * 0.5, y: size * 0.7)

                HStack(spacing: size * 0.4) {
                    Circle().fill(Color(hex: 0xFF9FC1).opacity(0.7))
                    Circle().fill(Color(hex: 0xFF9FC1).opacity(0.7))
                }
                .frame(width: size * 0.38, height: size * 0.055)
                .position(x: size * 0.5, y: size * 0.64)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func eye(size: CGFloat) -> some View {
        Circle()
            .fill(Color(hex: 0x25345F))
            .frame(width: size * 0.09, height: size * 0.115)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.03, height: size * 0.03)
                    .offset(x: -size * 0.018, y: size * 0.015)
            }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

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
