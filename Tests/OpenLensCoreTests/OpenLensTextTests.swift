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
        XCTAssertTrue(pages.allSatisfy { $0.count <= OpenLensText.linesPerPage && $0.allSatisfy { $0.count <= OpenLensText.lineWidth } })
        let reconstructed = pages.flatMap { $0 }.joined(separator: " ")
        XCTAssertTrue(reconstructed.contains("42 lazy dogs."))
        XCTAssertTrue(reconstructed.hasSuffix("dogs."))
    }
    func testLongUnbrokenWordIsNotDropped() {
        let word = String(repeating: "A", count: 71)
        let lines = OpenLensText.lines(word)
        XCTAssertEqual(lines.map(\.count), Array(repeating: 11, count: 6) + [5])
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

    func testBitmapTextUsesScreenAreaAndReadableFontSizes() {
        XCTAssertEqual(OpenLensTextSize.allCases.map(\.fontHeight), [30, 42, 56])
        XCTAssertEqual(OpenLensTextSize.allCases.map(\.name), ["Small", "Medium", "Large"])
        XCTAssertEqual(OpenLensTextSize.medium.fontHeight, 42)
        XCTAssertEqual(OpenLensDisplayGeometry.textImageWidth, 304)
        XCTAssertEqual(OpenLensDisplayGeometry.textImageHeight, 240)
        XCTAssertEqual(OpenLensDisplayGeometry.textImageX, 0)
        XCTAssertEqual(OpenLensDisplayGeometry.textImageY, 8)
        XCTAssertLessThanOrEqual(OpenLensDisplayGeometry.textImageY + OpenLensDisplayGeometry.textImageHeight,
                                OpenLensDisplayGeometry.screenHeight)
        for size in OpenLensTextSize.allCases {
            XCTAssertGreaterThan(size.charactersPerLine, 0)
            XCTAssertGreaterThan(size.linesPerPage, 0)
            XCTAssertLessThanOrEqual(size.firstLineY +
                (size.linesPerPage - 1) * size.lineSpacing + size.fontHeight,
                OpenLensDisplayGeometry.textImageHeight)
            // Monospaced glyphs are about 0.6*font size wide; enough safety for wide glyphs.
            let textWidth = Double(size.charactersPerLine) * Double(size.fontHeight) * 0.61
            let availableWidth = Double(OpenLensDisplayGeometry.textImageWidth -
                                        2 * OpenLensDisplayGeometry.textInset)
            XCTAssertLessThanOrEqual(textWidth, availableWidth)
        }
    }

    func testActualProblemSentenceNotClippedOrReordered() {
        let original = "Hey my name is Shree"
        for size in OpenLensTextSize.allCases {
            let pages = OpenLensText.pages(original, size: size)
            let collected = pages.flatMap { $0 }.joined(separator: " ")
            XCTAssertEqual(collected, original, "Sentence unexpectedly clipped for \(size.name)")
            XCTAssertEqual(pages.count, 1, "Short sentence should be visible on one screen at \(size.name)")
            XCTAssertTrue(pages.flatMap { $0 }.last?.hasSuffix("Shree") ?? false)
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

    func testWalkingDirectionsNeverDropStreetNames() {
        let complete = "Turn right onto North Parham Road, continue onto West Broad Street, " +
                       "then turn left toward Three Chopt Road."
        for size in OpenLensTextSize.allCases {
            let pages = OpenLensText.pages(complete, size: size)
            let reconstructed = pages.flatMap { $0 }.joined()
            let expected = OpenLensText.sanitize(complete)
            XCTAssertEqual(reconstructed.filter { !$0.isWhitespace },
                           expected.filter { !$0.isWhitespace },
                           "A road name or trailing direction was lost at \(size.name)")
            XCTAssertTrue(reconstructed.hasSuffix("Road."))
            XCTAssertTrue(pages.allSatisfy { $0.count <= size.linesPerPage })
        }
    }

    func testLongStreetNameSplitStillPreservesFullSpelling() {
        let instruction = "Continue straight onto " +
                          "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890 Boulevard."
        for size in OpenLensTextSize.allCases {
            let pages = OpenLensText.pages(instruction, size: size)
            let allCharacters = pages.flatMap { $0 }.joined()
            XCTAssertTrue(allCharacters.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"))
            XCTAssertTrue(allCharacters.hasSuffix("Boulevard."))
        }
    }

    func testNavigationAutofitIncludesCompleteStreetName() {
        let direction = "Turn left onto North Parham Road and continue to West Broad Street"
        let selected = OpenLensText.bestFittingSize(direction, preferred: .large)
        XCTAssertNotEqual(selected, .large)
        let pages = OpenLensText.pages(direction, size: selected)
        XCTAssertEqual(pages.count, 1,
            "Auto-fit should fit complete road names on the first page whenever possible")
        let shown = pages.flatMap { $0 }.joined()
        XCTAssertTrue(shown.contains("Broad Street") || shown.replacingOccurrences(of: " ", with: "").contains("BroadStreet"))
        XCTAssertEqual(shown.filter { !$0.isWhitespace },
                       direction.filter { !$0.isWhitespace })
    }

    func testNavigationAutofitRespectsUserPreferredSmallSize() {
        let direction = "Turn onto Broad Street"
        XCTAssertEqual(OpenLensText.bestFittingSize(direction, preferred: .small), .small)
    }

    func testAIProviderRequiresExplicitCloudSelection() {
        XCTAssertEqual(OpenLensAIProvider(rawValue: 0), .automatic)
        XCTAssertEqual(OpenLensAIProvider(rawValue: 1), .iphone)
        XCTAssertEqual(OpenLensAIProvider(rawValue: 2), .localMac)
        XCTAssertEqual(OpenLensAIProvider(rawValue: 3), .cloudRelay)
        XCTAssertEqual(OpenLensAIProvider.allCases.map(\.title),
                       ["Auto", "iPhone", "Mac", "Cloud"])
    }

    func testAllAIActionPromptsAreDistinctAndDoNotPromiseCameraOrInternet() {
        XCTAssertEqual(OpenLensAIPrompt.tasks.count, 5)
        let generated = OpenLensAIPrompt.tasks.map {
            OpenLensAIPrompt.instructions(mode: "ai", task: $0)
        }
        XCTAssertEqual(Set(generated).count, 5)
        for content in generated {
            XCTAssertTrue(content.contains("smart-glasses"))
            XCTAssertTrue(content.contains("do not invent recent facts"))
            XCTAssertFalse(content.contains("API key"))
        }
        XCTAssertFalse(OpenLensAIPrompt.isValid(task: "unsafe"))
        XCTAssertTrue(OpenLensAIPrompt.isValid(task: "summarize"))
    }

    func testOfflineTranslationPromptsExplicitlyPreserveProperNouns() {
        for (code, language) in OpenLensAIPrompt.translationLanguages {
            let instruction = OpenLensAIPrompt.instructions(mode: "translate",
                                                           task: "general",
                                                           targetLanguage: code)
            XCTAssertTrue(instruction.contains(language))
            XCTAssertTrue(instruction.contains("addresses"))
            XCTAssertTrue(instruction.contains("street names"))
        }
    }

    func testSharedClipRejectsEmptyTextAndWhitespace() {
        XCTAssertNil(OpenLensSharedClip(source: "Messages", text: "  \n \t "))
        XCTAssertNil(OpenLensSharedClip(source: "WhatsApp", text: ""))
    }
    func testSharedClipKeepsMessageContentWithoutAlteration() {
        let text = "Hey, meet on Broad Street at 6:15!\nDon't forget the address."
        let clip = OpenLensSharedClip(source: "Messages", text: text)
        XCTAssertNotNil(clip)
        XCTAssertEqual(clip?.source, "Messages")
        XCTAssertEqual(clip?.body, text)
        XCTAssertTrue(clip?.body.contains("Broad Street") ?? false)
    }
    func testSharedClipUnknownAppCannotSpoofSupportedSource() {
        let clip = OpenLensSharedClip(source: "Untrusted App", text: "Hello")
        XCTAssertEqual(clip?.source, "Other")
        XCTAssertEqual(OpenLensSharedClip.sourceChoices,
                       ["Messages", "WhatsApp", "Mail", "Notes", "Safari", "Other"])
    }
    func testSharedClipBoundsSavedContentSizeWithoutAffectingOriginalPaste() {
        let long = String(repeating: "a", count: 5000) + "THE END"
        let clip = OpenLensSharedClip(source: "Notes", text: long)
        XCTAssertEqual(clip?.body.count, OpenLensSharedClip.maxCharacters)
        XCTAssertEqual(long.count, 5007)
        XCTAssertEqual(clip?.body.last, "a")
    }
    func testSharedClipRoundTripsUnicodeLocally() throws {
        let clip = try XCTUnwrap(OpenLensSharedClip(
            source: "WhatsApp", text: "Hello नमस्ते తెలుగు 😃 / https://example.com"))
        let bytes = try JSONEncoder().encode(clip)
        let restored = try JSONDecoder().decode(OpenLensSharedClip.self, from: bytes)
        XCTAssertEqual(clip, restored)
        XCTAssertEqual(restored.body, "Hello नमस्ते తెలుగు 😃 / https://example.com")
    }
    func testSharedClipStorageCapsItemsAndOrdersNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clips = (0..<45).compactMap { idx in
            OpenLensSharedClip(source: "Other", text: "Item \(idx)",
                               createdAt: now.addingTimeInterval(Double(idx)))
        }
        let bounded = OpenLensSharedClip.limited(clips)
        XCTAssertEqual(bounded.count, OpenLensSharedClip.maxSavedItems)
        XCTAssertEqual(bounded.first?.body, "Item 44")
        XCTAssertEqual(bounded.last?.body, "Item 15")
        XCTAssertEqual(bounded.count, Set(bounded.map { $0.id }).count)
    }

    func testCardsJSONRoundTrip() throws {
        let card = OpenLensCard(title: "Meeting", body: "Remember the intro")
        let payload = try JSONEncoder().encode([card])
        XCTAssertEqual(try JSONDecoder().decode([OpenLensCard].self, from: payload), [card])
    }
}
