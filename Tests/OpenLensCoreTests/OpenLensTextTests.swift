import XCTest
@testable import OpenLensCore

final class OpenLensTextTests: XCTestCase {
    func testShortMessageHasOnePage() {
        XCTAssertEqual(OpenLensText.pages("HELLO WORLD", size: .small), [["HELLO WORLD"]])
    }
    func testEveryLineFitsAndWordsArePreserved() {
        let long = Array(repeating: "The quick brown fox jumped over 42 lazy dogs.", count: 16).joined(separator: " ")
        let pages = OpenLensText.pages(long)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 4 && $0.allSatisfy { $0.count <= OpenLensText.lineWidth } })
        let reconstructed = pages.flatMap { $0 }.joined(separator: " ")
        XCTAssertTrue(reconstructed.contains("42 lazy dogs."))
        XCTAssertTrue(reconstructed.hasSuffix("dogs."))
    }
    func testLongUnbrokenWordIsNotDropped() {
        let word = String(repeating: "A", count: 71)
        let lines = OpenLensText.lines(word)
        XCTAssertEqual(lines.map(\.count), Array(repeating: 9, count: 7) + [8])
        XCTAssertEqual(lines.joined(), word)
    }
    func testUnsupportedCharactersAreSafe() {
        let s = OpenLensText.sanitize("café • 東京 😃")
        XCTAssertTrue(s.hasPrefix("cafe"))
        XCTAssertTrue(s.unicodeScalars.allSatisfy { $0.isASCII })
    }
    func testParagraphsAndEmptyString() {
        XCTAssertEqual(OpenLensText.lines("Hello\nWorld"), ["Hello", "World"])
        XCTAssertEqual(OpenLensText.pages(""), [[""]])
    }
    func testRomanizesIndicScriptsForLegacyHUD() {
        XCTAssertEqual(OpenLensText.sanitize("नमस्ते"), "namaste")
        XCTAssertEqual(OpenLensText.sanitize("నమస్తే"), "namaste")
    }
    func testCountdownNeverGoesNegative() {
        XCTAssertEqual(OpenLensText.countdown(-100), "00:00")
        XCTAssertEqual(OpenLensText.countdown(90.2), "01:31")
        XCTAssertEqual(OpenLensText.countdown(600), "10:00")
    }
    func testDitheringProducesOnly1BitPixels() {
        let input = Array(repeating: 127.0, count: 64)
        let result = OpenLensText.dither(input, width: 8)
        XCTAssertEqual(result.count, input.count)
        XCTAssertTrue(result.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertTrue(result.contains(0) && result.contains(255))
        XCTAssertEqual(OpenLensText.dither([0, 255, 0, 255], width: 2), [0, 255, 0, 255])
        XCTAssertEqual(OpenLensText.dither(input, width: 0), [])
    }
    func testPhotoSizesAreCenteredAndWithinScreen() {
        for size in OpenLensDisplayGeometry.photoSizes {
            XCTAssertEqual(size.width % 8, 0)
            XCTAssertEqual(size.height % 8, 0)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertGreaterThanOrEqual(size.originX, 0)
            XCTAssertGreaterThanOrEqual(size.originY, 0)
            XCTAssertLessThanOrEqual(size.originX + size.width, OpenLensDisplayGeometry.screenWidth)
            XCTAssertLessThanOrEqual(size.originY + size.height, OpenLensDisplayGeometry.screenHeight)
        }
        XCTAssertEqual(OpenLensDisplayGeometry.photoSizes[2].originX, 32)
        XCTAssertEqual(OpenLensDisplayGeometry.photoSizes[2].originY, 32)
    }
    func testConservativeTextLayout() {
        XCTAssertEqual(OpenLensText.lineWidth, OpenLensTextSize.medium.charactersPerLine)
        XCTAssertLessThan(OpenLensDisplayGeometry.defaultTextX + OpenLensText.lineWidth * 14, 304)
        XCTAssertLessThan(OpenLensDisplayGeometry.bodyStartY + OpenLensDisplayGeometry.bodyLineSpacing * 3 + 24, 256)
    }

    func testAllTextSizesHaveRealSDKFontsAndSafePageGeometry() {
        XCTAssertEqual(OpenLensTextSize.allCases.map(\.fontID), [0, 2, 3])
        XCTAssertEqual(OpenLensTextSize.allCases.map(\.fontHeight), [24, 35, 49])
        XCTAssertEqual(OpenLensTextSize.allCases.map(\.name), ["Small", "Medium", "Large"])
        XCTAssertEqual(OpenLensTextSize.medium.fontHeight, 35)
        for size in OpenLensTextSize.allCases {
            XCTAssertGreaterThan(size.charactersPerLine, 0)
            XCTAssertGreaterThan(size.linesPerPage, 0)
            XCTAssertLessThanOrEqual(size.firstLineY + (size.linesPerPage - 1) * size.lineSpacing + size.fontHeight, 256)
            XCTAssertLessThanOrEqual(42 + size.charactersPerLine * (size.fontHeight / 2), 304)
        }
    }

    func testAllSizePresetsPreserveEveryCharacterAcrossPages() {
        let original = "MESSAGE ONE A very long explanation follows with words and numbers 12345. " +
                       String(repeating: "XYZ", count: 42) + " END OF MESSAGE!"
        for size in OpenLensTextSize.allCases {
            let pages = OpenLensText.pages(original, size: size)
            XCTAssertGreaterThan(pages.count, 1)
            XCTAssertTrue(pages.allSatisfy { $0.count <= size.linesPerPage })
            XCTAssertTrue(pages.flatMap { $0 }.allSatisfy { $0.count <= size.charactersPerLine })
            let normalized = OpenLensText.sanitize(original).filter { !$0.isWhitespace }
            let recovered = pages.flatMap { $0 }.joined().filter { !$0.isWhitespace }
            XCTAssertEqual(recovered, normalized, "Missing characters at size: \(size.name)")
            XCTAssertTrue(recovered.hasSuffix("ENDOFMESSAGE!"), "End was dropped for \(size.name)")
        }
    }

    func testMorePagesAtLargerTextSizes() {
        let message = String(repeating: "HELLO WORLD AGAIN ", count: 28)
        let counts = OpenLensTextSize.allCases.map { OpenLensText.pages(message, size: $0).count }
        XCTAssertLessThan(counts[0], counts[1])
        XCTAssertLessThan(counts[1], counts[2])
    }

    func testLargeFontLongWordsDoNotLoseTrailingCharacters() {
        let word = String(repeating: "X", count: 151) + "Z"
        let pages = OpenLensText.pages(word, size: .large)
        XCTAssertEqual(pages.flatMap { $0 }.joined(), word)
        XCTAssertEqual(pages.last?.last?.last, "Z")
    }

    func testCardsJSONRoundTrip() throws {
        let card = OpenLensCard(title: "Meeting", body: "Remember the intro")
        let payload = try JSONEncoder().encode([card])
        XCTAssertEqual(try JSONDecoder().decode([OpenLensCard].self, from: payload), [card])
    }
}
