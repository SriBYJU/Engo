import XCTest
@testable import OpenLensCore

final class OpenLensTextTests: XCTestCase {
    func testShortMessageHasOnePage() {
        XCTAssertEqual(OpenLensText.pages("HELLO WORLD"), [["HELLO WORLD"]])
    }
    func testEveryLineFitsAndWordsArePreserved() {
        let long = Array(repeating: "The quick brown fox jumped over 42 lazy dogs.", count: 16).joined(separator: " ")
        let pages = OpenLensText.pages(long)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 4 && $0.allSatisfy { $0.count <= 23 } })
        let reconstructed = pages.flatMap { $0 }.joined(separator: " ")
        XCTAssertTrue(reconstructed.contains("42 lazy dogs."))
        XCTAssertTrue(reconstructed.hasSuffix("dogs."))
    }
    func testLongUnbrokenWordIsNotDropped() {
        let word = String(repeating: "A", count: 71)
        let lines = OpenLensText.lines(word)
        XCTAssertEqual(lines.map(\.count), [23,23,23,2])
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
    func testCardsJSONRoundTrip() throws {
        let card = OpenLensCard(title: "Meeting", body: "Remember the intro")
        let payload = try JSONEncoder().encode([card])
        XCTAssertEqual(try JSONDecoder().decode([OpenLensCard].self, from: payload), [card])
    }
}
