import AppKit
import SwiftUI

@MainActor
private struct BerryLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
private struct BlueberryArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.27, green: 0.80, blue: 0.98),
                             Color(red: 0.23, green: 0.46, blue: 0.96),
                             Color(red: 0.39, green: 0.31, blue: 0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: size * 0.82, height: size * 0.82)

                ZStack {
                    Ellipse()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.36, green: 0.77, blue: 1.0),
                                     Color(red: 0.30, green: 0.48, blue: 0.96),
                                     Color(red: 0.36, green: 0.30, blue: 0.77)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: size * 0.78, height: size * 0.80)
                        .offset(y: size * 0.09)

                    Ellipse()
                        .fill(.white.opacity(0.38))
                        .frame(width: size * 0.30, height: size * 0.19)
                        .rotationEffect(.degrees(-28))
                        .offset(x: -size * 0.19, y: -size * 0.19)

                    Ellipse()
                        .stroke(.white.opacity(0.8), lineWidth: size * 0.018)
                        .frame(width: size * 0.78, height: size * 0.80)
                        .offset(y: size * 0.09)

                    HStack(spacing: size * -0.07) {
                        BerryLeaf()
                            .fill(Color(red: 0.49, green: 0.86, blue: 1.0))
                            .frame(width: size * 0.12, height: size * 0.15)
                            .rotationEffect(.degrees(-38))
                        BerryLeaf()
                            .fill(Color(red: 0.69, green: 0.91, blue: 1.0))
                            .frame(width: size * 0.12, height: size * 0.15)
                        BerryLeaf()
                            .fill(Color(red: 0.49, green: 0.86, blue: 1.0))
                            .frame(width: size * 0.12, height: size * 0.15)
                            .rotationEffect(.degrees(38))
                    }
                    .position(x: size * 0.5, y: size * 0.15)

                    HStack(spacing: size * 0.22) {
                        eye(size: size)
                        eye(size: size)
                    }
                    .position(x: size * 0.5, y: size * 0.43)

                    HStack(spacing: size * 0.42) {
                        Ellipse()
                            .fill(Color(red: 1.0, green: 0.73, blue: 0.86).opacity(0.82))
                            .frame(width: size * 0.12, height: size * 0.065)
                        Ellipse()
                            .fill(Color(red: 1.0, green: 0.73, blue: 0.86).opacity(0.82))
                            .frame(width: size * 0.12, height: size * 0.065)
                    }
                    .position(x: size * 0.5, y: size * 0.59)

                    Path { path in
                        path.move(to: CGPoint(x: size * 0.42, y: size * 0.65))
                        path.addQuadCurve(
                            to: CGPoint(x: size * 0.58, y: size * 0.65),
                            control: CGPoint(x: size * 0.5, y: size * 0.73)
                        )
                    }
                    .stroke(Color(red: 0.10, green: 0.16, blue: 0.38),
                            style: StrokeStyle(lineWidth: size * 0.022, lineCap: .round))
                }
                .frame(width: size * 0.86, height: size * 0.86)
                .shadow(color: Color(red: 0.08, green: 0.13, blue: 0.39).opacity(0.25),
                        radius: size * 0.035, y: size * 0.025)

                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.11, weight: .black))
                    .foregroundStyle(.white.opacity(0.95))
                    .position(x: size * 0.82, y: size * 0.22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func eye(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.10, green: 0.16, blue: 0.38))
                .frame(width: size * 0.105, height: size * 0.12)
            Circle()
                .fill(.white)
                .frame(width: size * 0.038, height: size * 0.038)
                .offset(x: -size * 0.021, y: -size * 0.022)
        }
    }
}

@MainActor
private func renderIcons() throws {
    let renderer = ImageRenderer(content: BlueberryArtwork().frame(width: 1024, height: 1024))
    renderer.scale = 1
    renderer.isOpaque = true

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render the Tvo blueberry icon.")
    }

    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for relativePath in [
        "iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "iOS/Assets.xcassets/TvoLogo.imageset/TvoLogo.png",
    ] {
        try png.write(to: root.appendingPathComponent(relativePath), options: .atomic)
    }
}

try await renderIcons()
