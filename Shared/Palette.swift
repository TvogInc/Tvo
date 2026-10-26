import Foundation

import Foundation

/// Blueberry colors from the design canvas, as 0xRRGGBB.
public enum Palette {
    public static let characterColorKey = "tvo.characterColor"
    public static let berry1: UInt32 = 0xA9BCFF  // light periwinkle
    public static let berry2: UInt32 = 0x6C86F5
    public static let berry3: UInt32 = 0x4254D6
    public static let berry4: UInt32 = 0x2B2F8F  // deep indigo
    public static let nose: UInt32 = 0x1C1F66
    public static let ink: UInt32 = 0x17151F
    public static let inkSoft: UInt32 = 0xB9B2CC
    public static let panel: UInt32 = 0x1E1B29

    public static var gradient: [UInt32] {
        guard let stored = UserDefaults.standard.string(forKey: characterColorKey),
              let color = UInt32(stored, radix: 16), color <= 0xFFFFFF else {
            return [berry1, berry2, berry3, berry4]
        }
        return [
            blend(color, with: 0xFFFFFF, amount: 0.24),
            color,
            blend(color, with: 0x000000, amount: 0.22),
            blend(color, with: 0x000000, amount: 0.48),
        ]
    }

    public static var characterColorName: String {
        guard let stored = UserDefaults.standard.string(forKey: characterColorKey),
              let color = UInt32(stored, radix: 16), color <= 0xFFFFFF else {
            return "blue"
        }

        let (red, green, blue) = rgb(color)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let difference = maximum - minimum
        let brightness = maximum
        let saturation = maximum == 0 ? 0 : difference / maximum

        if brightness < 0.16 { return "black" }
        if saturation < 0.12 { return brightness > 0.88 ? "white" : "gray" }

        let hue: Double
        if difference == 0 {
            hue = 0
        } else if maximum == red {
            hue = 60 * ((green - blue) / difference).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = 60 * ((blue - red) / difference + 2)
        } else {
            hue = 60 * ((red - green) / difference + 4)
        }
        let degrees = (hue + 360).truncatingRemainder(dividingBy: 360)

        if brightness < 0.48 && degrees >= 10 && degrees < 50 { return "brown" }
        switch degrees {
        case 10..<40: return "orange"
        case 40..<70: return "yellow"
        case 70..<150: return "green"
        case 150..<190: return "teal"
        case 190..<210: return "cyan"
        case 210..<255: return "blue"
        case 255..<280: return "indigo"
        case 280..<320: return "purple"
        case 320..<345: return "pink"
        default: return "red"
        }
    }

    public static var characterDescription: String {
        let color = characterColorName
        let article = "aeiou".contains(color.first ?? " ") ? "an" : "a"
        return "\(article) \(color) blueberry"
    }

    public static let gradientStops: [Double] = [0, 0.34, 0.68, 1]

    public static func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func blend(_ color: UInt32, with other: UInt32, amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let first = Double((color >> shift) & 0xFF)
            let second = Double((other >> shift) & 0xFF)
            return UInt32((first + (second - first) * amount).rounded())
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }
}
