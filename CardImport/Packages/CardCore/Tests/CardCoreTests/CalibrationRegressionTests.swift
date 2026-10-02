import XCTest
@testable import CardCore

/// Regressions found by the benchmark.
final class CalibrationRegressionTests: XCTestCase {
    func testCountryCodeWithoutPlus() {
        XCTAssertEqual(PhoneNormalizer.normalize("(852) 2560 7397", regionHint: "CA")?.e164, "+85225607397")
        XCTAssertEqual(PhoneNormalizer.normalize("886-2-2345-6789", regionHint: "CA")?.e164, "+886223456789")
        XCTAssertEqual(PhoneNormalizer.normalize("86 21 6123 4567", regionHint: "CA")?.e164, "+862161234567")
        XCTAssertTrue(PhoneNormalizer.normalize("(852) 2560 7397", regionHint: "CA")?.isValid ?? false)
        // A national number must not be mistaken for a country code.
        XCTAssertEqual(PhoneNormalizer.normalize("905-555-0193", regionHint: "CA")?.e164, "+19055550193")
    }

    func testWeakOCRDoesNotPunishCorrectValues() {
        // OCR that read almost nothing (blurry photo): its silence must not push correct values into review.
        let card = F.johnFront()
        let weak = OCRResult(engine: "t", lines: [OCRLine(text: "Jo", confidence: 0.3), OCRLine(text: "ABC", confidence: 0.3),
                                                  OCRLine(text: "4l6-5", confidence: 0.2), OCRLine(text: "www", confidence: 0.2)])
        XCTAssertLessThan(OCRReliability.estimate(card: card, ocr: weak), 0.3)
        let d = CardScorer().score(F.obs("a", 0, card, weak))
        XCTAssertTrue(ReviewPolicy().evaluate(d).review.isEmpty, "\(ReviewPolicy().evaluate(d).review.map(\.field))")
        // A good OCR that misses a value is real evidence.
        var good = F.johnOCR()
        good.lines.removeAll { $0.text == "Sales Manager" }
        let d2 = CardScorer().score(F.obs("a", 0, card, good))
        XCTAssertLessThan(d2.jobTitle!.confidence, d.jobTitle!.confidence)
    }

    func testWeakSignalsAloneNeverMerge() {
        // Two unrelated nameless backs shot 5 s apart with the same colours: no content link → no merge.
        let a = ExtractedCard(cardSide: .back, websites: [ExtractedWebsite(url: "www.alpha.com", confidence: 0.98)])
        let b = ExtractedCard(cardSide: .back, addresses: [ExtractedAddress(street: "1 Main St", city: "Toronto", confidence: 0.95)])
        let front = ExtractedCard(cardSide: .front, name: ExtractedName(given: F.fv("Ann"), family: F.fv("Ho")),
                                  emails: [ExtractedEmail(address: "ann@beta.com", confidence: 0.98)])
        let items = [(F.obs("f", 0, front, nil, t: 100), front), (F.obs("a", 1, a, nil, t: 105), a), (F.obs("b", 2, b, nil, t: 110), b)]
            .map { ($0.0, CardScorer().score($0.0)) }
        let r = FrontBackMatcher().group(items)
        XCTAssertFalse(r.groups.contains { $0.contains("f") && ($0.contains("a") || $0.contains("b")) }, "\(r.groups)")
    }

    func testSurnameOnlyCrossScriptIsWeak() {
        let en = ExtractedCard(cardSide: .front, name: ExtractedName(given: F.fv("Kevin"), family: F.fv("Wang")))
        let zh = ExtractedCard(cardSide: .front, name: ExtractedName(cjkFull: F.fv("王志明")))
        let e = FrontBackMatcher().pairEvidence((F.obs("a", 0, en), CardScorer().score(F.obs("a", 0, en))),
                                               (F.obs("b", 1, zh), CardScorer().score(F.obs("b", 1, zh))))
        XCTAssertLessThan(e.contentScore, 1.5)
        let zh2 = ExtractedCard(cardSide: .front, name: ExtractedName(cjkFull: F.fv("王凱文")))
        _ = zh2
        let full = ExtractedCard(cardSide: .front, name: ExtractedName(given: F.fv("Zhiming"), family: F.fv("Wang")))
        let e2 = FrontBackMatcher().pairEvidence((F.obs("a", 0, full), CardScorer().score(F.obs("a", 0, full))),
                                                (F.obs("b", 1, zh), CardScorer().score(F.obs("b", 1, zh))))
        XCTAssertGreaterThanOrEqual(e2.contentScore, 2.5)
    }

    func testVariantCharactersAreNotAgreement() async throws {
        // First reader: 恒 (0.85). Second reader: 恆. Must stay in review, not be "confirmed".
        var card = F.wangFrontZH()
        card.companyCjk = F.fv("恒昌國際貿易有限公司", 0.85, alts: ["恆昌國際貿易有限公司"])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = InMemoryAddressBook()
        let verifier = FakeVerifier { label, _ in
            label.hasPrefix("公司") ? VerifierAnswer(value: "恆昌國際貿易有限公司", confidence: 0.9) : VerifierAnswer(value: nil, confidence: 0)
        }
        let p = BatchProcessor(store: BatchStore(directory: dir), images: FakeImages(), ocr: nil, extractor: FakeExtractor(["x": card]),
                               verifier: verifier, resolver: nil, index: book, writer: book)
        let s = await p.run(BatchState(source: "t", photos: [PhotoRecord(id: "x", index: 0)]))
        let written = await book.contacts.first?.draft
        // The verifier picked the first reader's alternative → the alternative is used, never the unconfirmed 恒.
        XCTAssertNotEqual(written?.companyCJK?.value, "恒昌國際貿易有限公司")
        XCTAssertTrue(written?.companyCJK?.value == "恆昌國際貿易有限公司" || s.review.contains { $0.field == "company_cjk" })
    }

    func testPhoneCandidateShowsExtension() {
        var d = ContactDraft(id: "x", photoIDs: [])
        d.phones = [DraftPhone(kind: .work, e164: "+16045550117", printed: "+1 604 555 0117", extensionNumber: "746", confidence: 0.5)]
        XCTAssertEqual(d.allFields().first?.1, "+1 604 555 0117 ext. 746")
    }
}

final class NameIdentityTests: XCTestCase {
    func testOneLetterDifferentNamesAreDifferentPeople() {
        let a = ExtractedCard(cardSide: .front, name: ExtractedName(given: F.fv("Kevin"), family: F.fv("Chang")),
                              emails: [ExtractedEmail(address: "kevin@dawnlight.design", confidence: 0.98)])
        let b = ExtractedCard(cardSide: .front, name: ExtractedName(given: F.fv("Kevin"), family: F.fv("Zhang")),
                              emails: [ExtractedEmail(address: "kevin.zhang@harbourviewfoods.ca", confidence: 0.98)])
        let e = FrontBackMatcher().pairEvidence((F.obs("a", 0, a), CardScorer().score(F.obs("a", 0, a))),
                                               (F.obs("b", 1, b), CardScorer().score(F.obs("b", 1, b))))
        XCTAssertTrue(e.conflict || e.score < 0, "\(e)")
        let c = ExtractedCard(cardSide: .front, name: ExtractedName(cjkFull: F.fv("王大明")))
        let d = ExtractedCard(cardSide: .front, name: ExtractedName(cjkFull: F.fv("王小明")))
        let e2 = FrontBackMatcher().pairEvidence((F.obs("c", 0, c), CardScorer().score(F.obs("c", 0, c))),
                                                (F.obs("d", 1, d), CardScorer().score(F.obs("d", 1, d))))
        XCTAssertTrue(e2.conflict)
        // Simplified vs Traditional printing of the same name is the same person.
        let t = ExtractedCard(cardSide: .front, name: ExtractedName(cjkFull: F.fv("陳建華")))
        let s = ExtractedCard(cardSide: .back, name: ExtractedName(cjkFull: F.fv("陈建华")))
        let e3 = FrontBackMatcher().pairEvidence((F.obs("t", 0, t), CardScorer().score(F.obs("t", 0, t))),
                                                (F.obs("s", 1, s), CardScorer().score(F.obs("s", 1, s))))
        XCTAssertTrue(e3.signals.contains("same_name"))
    }
}
