import AppKit
import Foundation

struct ClipboardHistoryRGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

struct ClipboardHistoryColorPresentation: Equatable, Sendable {
    let color: ClipboardHistoryRGBColor
    let hex: String
    let red: Int
    let green: Int
    let blue: Int
    let hue: Int
    let hslSaturation: Int
    let lightness: Int
    let hsbSaturation: Int
    let brightness: Int

    init?(text: String?) {
        guard var raw = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }

        red = (value >> 16) & 0xff
        green = (value >> 8) & 0xff
        blue = value & 0xff
        color = ClipboardHistoryRGBColor(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
        hex = String(format: "#%02X%02X%02X", red, green, blue)

        let hsb = Self.hsb(for: color)
        hue = Int((hsb.hue * 360).rounded()) % 360
        hsbSaturation = Int((hsb.saturation * 100).rounded())
        brightness = Int((hsb.brightness * 100).rounded())

        let maximum = max(color.red, max(color.green, color.blue))
        let minimum = min(color.red, min(color.green, color.blue))
        let lightnessValue = (maximum + minimum) / 2
        hslSaturation = hsbSaturation
        lightness = Int((lightnessValue * 100).rounded())
    }

    var rgbDescription: String { "RGB \(red), \(green), \(blue)" }
    var hslDescription: String { "HSL \(hue), \(hslSaturation), \(lightness)" }
    var hsbDescription: String { "HSB \(hue), \(hsbSaturation), \(brightness)" }

    var foregroundColor: NSColor {
        color.relativeLuminance > 0.48 ? .black : .white
    }

    fileprivate static func hsb(
        for color: ClipboardHistoryRGBColor
    ) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(color.red, max(color.green, color.blue))
        let minimum = min(color.red, min(color.green, color.blue))
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == color.red {
                hue = ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == color.green {
                hue = (color.blue - color.red) / delta + 2
            } else {
                hue = (color.red - color.green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }
}

enum ClipboardHistoryIconPalette {
    struct Sample: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private struct Bucket {
        var weight = 0.0
        var hueX = 0.0
        var hueY = 0.0
        var saturation = 0.0
        var brightness = 0.0
    }

    static let monochromeFallback = ClipboardHistoryRGBColor(
        red: 0.035,
        green: 0.09,
        blue: 0.24
    )

    static func representativeColor(samples: [Sample]) -> ClipboardHistoryRGBColor {
        var buckets = Array(repeating: Bucket(), count: 12)
        var totalVisibleWeight = 0.0

        for sample in samples where sample.alpha >= 0.15 {
            totalVisibleWeight += sample.alpha
            let color = ClipboardHistoryRGBColor(
                red: sample.red,
                green: sample.green,
                blue: sample.blue
            )
            let hsb = ClipboardHistoryColorPresentation.hsb(for: color)
            guard hsb.saturation >= 0.18,
                  hsb.brightness >= 0.12,
                  !(hsb.brightness > 0.94 && hsb.saturation < 0.28) else { continue }

            let index = min(11, Int(hsb.hue * 12))
            let weight = sample.alpha * (0.35 + hsb.saturation) * (0.45 + hsb.brightness)
            let angle = hsb.hue * 2 * .pi
            buckets[index].weight += weight
            buckets[index].hueX += cos(angle) * weight
            buckets[index].hueY += sin(angle) * weight
            buckets[index].saturation += hsb.saturation * weight
            buckets[index].brightness += hsb.brightness * weight
        }

        guard let bucket = buckets.max(by: { $0.weight < $1.weight }),
              bucket.weight >= max(0.25, totalVisibleWeight * 0.025) else {
            return monochromeFallback
        }

        var hue = atan2(bucket.hueY, bucket.hueX) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let saturation = min(max(bucket.saturation / bucket.weight, 0.58), 0.88)
        let brightness = min(max(bucket.brightness / bucket.weight, 0.38), 0.78)
        return rgb(hue: hue, saturation: saturation, brightness: brightness)
    }

    static func representativeColor(image: NSImage) -> ClipboardHistoryRGBColor {
        let size = 32
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return monochromeFallback }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: CGRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var samples: [Sample] = []
        samples.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                samples.append(
                    Sample(
                        red: color.redComponent,
                        green: color.greenComponent,
                        blue: color.blueComponent,
                        alpha: color.alphaComponent
                    )
                )
            }
        }
        return representativeColor(samples: samples)
    }

    private static func rgb(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> ClipboardHistoryRGBColor {
        let scaledHue = hue * 6
        let sector = Int(floor(scaledHue)) % 6
        let fraction = scaledHue - floor(scaledHue)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - fraction * saturation)
        let t = brightness * (1 - (1 - fraction) * saturation)
        let components: (Double, Double, Double) = switch sector {
        case 0: (brightness, t, p)
        case 1: (q, brightness, p)
        case 2: (p, brightness, t)
        case 3: (p, q, brightness)
        case 4: (t, p, brightness)
        default: (brightness, p, q)
        }
        return ClipboardHistoryRGBColor(
            red: components.0,
            green: components.1,
            blue: components.2
        )
    }
}

struct ClipboardHistoryApplicationAppearance {
    let icon: NSImage
    let headerColor: NSColor
}

@MainActor
final class ClipboardHistoryApplicationAppearanceCache {
    private var values: [String: ClipboardHistoryApplicationAppearance] = [:]

    func appearance(for item: ClipboardHistoryItem) -> ClipboardHistoryApplicationAppearance? {
        guard let bundleIdentifier = item.sourceBundleIdentifier else { return nil }
        if let cached = values[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let appearance = ClipboardHistoryApplicationAppearance(
            icon: icon,
            headerColor: ClipboardHistoryIconPalette.representativeColor(image: icon).nsColor
        )
        values[bundleIdentifier] = appearance
        return appearance
    }
}

struct ClipboardHistoryTextMetrics: Equatable, Sendable {
    let characters: Int
    let words: Int
    let lines: Int

    init(text: String) {
        characters = text.count
        var wordCount = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) {
            _, _, _, _ in wordCount += 1
        }
        words = wordCount
        lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
    }

    var description: String {
        "\(characters) 个字符  ·  \(words) 单词  ·  \(lines) 行"
    }
}
