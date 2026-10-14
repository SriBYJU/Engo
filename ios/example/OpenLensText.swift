import Foundation

/// Pure Foundation rendering primitives shared by the iOS client and SwiftPM tests.
public enum OpenLensText {
    public static let lineWidth = 23
    public static let linesPerPage = 4

    /// The legacy hardware font only supports a limited ASCII subset.
    public static func sanitize(_ input: String) -> String {
        let ascii = input.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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
