import Foundation

/// Pure Foundation rendering primitives shared by the iOS client and SwiftPM tests.
/// OpenLens renders words into a 1-bit image using the *working photo path*.
/// The legacy SDK's native text commands caused rotated/clipped fragments.
/// Sizes are real UIKit bitmap font sizes, not the old SDK font indices.
public enum OpenLensTextSize: Int, CaseIterable {
    case small = 0, medium = 1, large = 2

    public var name: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    public var fontHeight: Int {
        switch self {
        case .small: return 30
        case .medium: return 42
        case .large: return 56
        }
    }
    /// Conservative character limits for a monospaced UIKit font in 304px.
    /// The renderer additionally verifies actual measured width before drawing.
    public var charactersPerLine: Int {
        switch self {
        case .small: return 15
        case .medium: return 11
        case .large: return 8
        }
    }
    public var linesPerPage: Int {
        switch self {
        case .small: return 6
        case .medium: return 4
        case .large: return 3
        }
    }
    public var firstLineY: Int { 8 }
    public var lineSpacing: Int {
        switch self {
        case .small: return 39
        case .medium: return 54
        case .large: return 72
        }
    }

    private static let key = "openlens.display.textSize"
    public static var selected: OpenLensTextSize {
        get {
            guard let raw = UserDefaults.standard.object(forKey: key) as? Int,
                  let size = OpenLensTextSize(rawValue: raw) else { return .medium }
            return size
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

public enum OpenLensText {
    public static let lineWidth = OpenLensTextSize.medium.charactersPerLine
    public static let linesPerPage = OpenLensTextSize.medium.linesPerPage

    /// The legacy hardware font only supports a limited ASCII subset.
    public static func sanitize(_ input: String) -> String {
        let romanized = input.applyingTransform(.toLatin, reverse: false) ?? input
        let ascii = romanized.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        for scalar in ascii.unicodeScalars {
            switch scalar.value {
            case 10, 13: result.append("\n")
            case 32...126: result.unicodeScalars.append(scalar)
            default: result.append(" ")
            }
        }
        return result
    }

    /// Wrap paragraphs without dropping words. Long words are chunked.
    public static func lines(_ message: String, width: Int = lineWidth) -> [String] {
        let maxWidth = max(1, width)
        var output: [String] = []
        for paragraph in sanitize(message).components(separatedBy: .newlines) {
            let words = paragraph.split(whereSeparator: { $0 == " " || $0 == "\t" })
            var line = ""
            for wordSlice in words {
                var word = String(wordSlice)
                while !word.isEmpty {
                    let room = maxWidth - line.count - (line.isEmpty ? 0 : 1)
                    if room <= 0 {
                        output.append(line)
                        line = ""
                        continue
                    }
                    if word.count <= room {
                        line += (line.isEmpty ? "" : " ") + word
                        word = ""
                    } else if line.isEmpty {
                        output.append(String(word.prefix(maxWidth)))
                        word.removeFirst(min(maxWidth, word.count))
                    } else {
                        output.append(line)
                        line = ""
                    }
                }
            }
            if !line.isEmpty { output.append(line) }
            else if words.isEmpty { output.append("") }
        }
        return output.isEmpty ? [""] : output
    }

    public static func pages(_ message: String, width: Int = lineWidth, height: Int = linesPerPage) -> [[String]] {
        let items = lines(message, width: width)
        let pageSize = max(1, height)
        return stride(from: 0, to: items.count, by: pageSize).map { start in
            Array(items[start..<min(items.count, start + pageSize)])
        }
    }

    public static func pages(_ message: String, size: OpenLensTextSize) -> [[String]] {
        pages(message, width: size.charactersPerLine, height: size.linesPerPage)
    }

    /// Navigation directions are different from free-form notes: whenever
    /// possible, include the complete street name on the first HUD screen.
    /// Never enlarge beyond the user's chosen font. If no size fits, return
    /// Small and keep all remaining text available through page controls.
    public static func bestFittingSize(_ message: String,
                                      preferred: OpenLensTextSize) -> OpenLensTextSize {
        let candidates = OpenLensTextSize.allCases
            .filter { $0.rawValue <= preferred.rawValue }
            .sorted { $0.rawValue > $1.rawValue }
        return candidates.first { pages(message, size: $0).count == 1 } ?? .small
    }

    /// Floyd–Steinberg dithering for black-and-white display previews.
    /// Every output pixel is exactly 0 or 255, suitable for the SDK 1bpp encoder.
    public static func dither(_ luminance: [Double], width: Int) -> [UInt8] {
        guard width > 0, !luminance.isEmpty else { return [] }
        var values = luminance.map { max(0, min(255, $0)) }
        var result = [UInt8](repeating: 0, count: values.count)
        for i in values.indices {
            let x = i % width
            let white = values[i] >= 127.5
            let output = white ? 255.0 : 0.0
            result[i] = white ? 255 : 0
            let error = values[i] - output
            if x + 1 < width && i + 1 < values.count { values[i + 1] += error * 7 / 16 }
            if x > 0 && i + width - 1 < values.count { values[i + width - 1] += error * 3 / 16 }
            if i + width < values.count { values[i + width] += error * 5 / 16 }
            if x + 1 < width && i + width + 1 < values.count { values[i + width + 1] += error / 16 }
        }
        return result
    }

    public static func countdown(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        let minutes = seconds / 60
        return String(format: "%02d:%02d", minutes, seconds % 60)
    }
}

public struct OpenLensCard: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var body: String

    public init(id: UUID = UUID(), title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// Default display is 304×256 pixels. Keep HUD text inside the optical safe area.
/// Presets for photos include an intentionally edge-to-edge mode, which can clip
/// through some frames' optical eyebox and may transfer more slowly over BLE.
public enum OpenLensDisplayGeometry {
    public static let screenWidth = 304
    public static let screenHeight = 256
    /// One full-screen streamed bitmap, centrally placed like a photo.
    public static let textImageWidth = 304
    public static let textImageHeight = 240
    public static let textImageX = 0
    public static let textImageY = 8
    public static let textInset = 10
    public static let defaultTextX = 48
    public static let headerY = 40
    public static let bodyStartY = 88
    public static let bodyLineSpacing = 36

    public struct PhotoSize: Equatable {
        public let name: String
        public let width: Int
        public let height: Int
        public var originX: Int { (screenWidth - width) / 2 }
        public var originY: Int { (screenHeight - height) / 2 }
        public var fullDisplay: Bool { width == screenWidth }
    }
    public static let photoSizes: [PhotoSize] = [
        PhotoSize(name: "Small", width: 160, height: 96),
        PhotoSize(name: "Medium", width: 208, height: 144),
        PhotoSize(name: "Large", width: 240, height: 192),
        PhotoSize(name: "Full", width: 304, height: 240)
    ]
}
