import Foundation
@testable import CardCore

enum F {
    static func fv(_ v: String, _ c: Double = 0.98, alts: [String] = []) -> FieldValue { FieldValue(v, confidence: c, alternatives: alts, sourceText: v) }

    /// A clean English front: name, title, company, mobile, email, website.
    static func johnFront(titleConf: Double = 0.98) -> ExtractedCard {
        ExtractedCard(cardSide: .front, languageHint: ["en"],
                      name: ExtractedName(given: fv("John"), family: fv("Chen")),
                      company: fv("ABC Foods Ltd."), jobTitle: fv("Sales Manager", titleConf, alts: titleConf < 0.9 ? ["Sales Director"] : []),
                      phones: [ExtractedPhone(kind: .mobile, number: "416-555-0137", confidence: 0.98, sourceText: "M 416-555-0137")],
                      emails: [ExtractedEmail(address: "john.chen@abcfoods.com", confidence: 0.98)],
                      websites: [ExtractedWebsite(url: "www.abcfoods.com", confidence: 0.97)])
    }

    static func johnOCR() -> OCRResult {
        OCRResult(engine: "test", lines: ["John Chen", "Sales Manager", "ABC Foods Ltd.", "M 416-555-0137", "john.chen@abcfoods.com",
                                          "www.abcfoods.com"].map { OCRLine(text: $0, confidence: 0.95) })
    }

    /// Nameless back: office phone, fax, address, same domain.
    static func johnBack() -> ExtractedCard {
        ExtractedCard(cardSide: .back, languageHint: ["en"], company: fv("ABC Foods Ltd."),
                      phones: [ExtractedPhone(kind: .work, number: "(416) 555-0100", confidence: 0.97, sourceText: "T (416) 555-0100"),
                               ExtractedPhone(kind: .fax, number: "(416) 555-0199", confidence: 0.97, sourceText: "F (416) 555-0199")],
                      websites: [ExtractedWebsite(url: "www.abcfoods.com", confidence: 0.97)],
                      addresses: [ExtractedAddress(street: "120 Front St W, Suite 400", city: "Toronto", region: "ON", postalCode: "M5J 2M2",
                                                   country: "Canada", formatted: "120 Front St W, Suite 400, Toronto, ON M5J 2M2", confidence: 0.95)])
    }

    static func johnBackOCR() -> OCRResult {
        OCRResult(engine: "test", lines: ["ABC Foods Ltd.", "T (416) 555-0100", "F (416) 555-0199", "120 Front St W, Suite 400",
                                          "Toronto, ON M5J 2M2", "www.abcfoods.com"].map { OCRLine(text: $0, confidence: 0.95) })
    }

    /// Colleague at the same company — must never be merged with John.
    static func maryFront() -> ExtractedCard {
        ExtractedCard(cardSide: .front, languageHint: ["en"], name: ExtractedName(given: fv("Mary"), family: fv("Lee")),
                      company: fv("ABC Foods Ltd."), jobTitle: fv("Purchasing Director"),
                      phones: [ExtractedPhone(kind: .work, number: "(416) 555-0100", confidence: 0.97, sourceText: "T (416) 555-0100"),
                               ExtractedPhone(kind: .mobile, number: "647-555-0142", confidence: 0.97, sourceText: "M 647-555-0142")],
                      emails: [ExtractedEmail(address: "mary.lee@abcfoods.com", confidence: 0.98)])
    }

    static func maryOCR() -> OCRResult {
        OCRResult(engine: "test", lines: ["Mary Lee", "Purchasing Director", "ABC Foods Ltd.", "T (416) 555-0100", "M 647-555-0142",
                                          "mary.lee@abcfoods.com"].map { OCRLine(text: $0, confidence: 0.95) })
    }

    /// Bilingual Taiwanese card: Chinese front, English back.
    static func wangFrontZH() -> ExtractedCard {
        ExtractedCard(cardSide: .front, languageHint: ["zh-Hant"], name: ExtractedName(cjkFull: fv("王大明")),
                      companyCjk: fv("大明食品股份有限公司"), jobTitleCjk: fv("業務經理"),
                      phones: [ExtractedPhone(kind: .mobile, number: "0912-345-678", confidence: 0.98, sourceText: "手機 0912-345-678")],
                      emails: [ExtractedEmail(address: "david@daming.com.tw", confidence: 0.98)])
    }

    static func wangBackEN() -> ExtractedCard {
        ExtractedCard(cardSide: .front, languageHint: ["en"], name: ExtractedName(given: fv("David"), family: fv("Wang")),
                      company: fv("Da Ming Foods Co., Ltd."), jobTitle: fv("Sales Manager"),
                      phones: [ExtractedPhone(kind: .mobile, number: "+886 912 345 678", confidence: 0.98, sourceText: "M +886 912 345 678")],
                      emails: [ExtractedEmail(address: "david@daming.com.tw", confidence: 0.98)])
    }

    static func obs(_ id: String, _ i: Int, _ c: ExtractedCard, _ o: OCRResult? = nil, t: TimeInterval? = nil) -> CardObservation {
        CardObservation(photoID: id, index: i, captureDate: t.map { Date(timeIntervalSince1970: $0) }, extraction: c, ocr: o)
    }
}

/// Fake extractor: returns canned cards per photo ID; can simulate failures.
final class FakeExtractor: CardExtractor, @unchecked Sendable {
    var cards: [String: ExtractedCard]
    var transientFor: Set<String> = []
    var permanentFor: Set<String> = []
    var unauthorized = false
    var calls: [String] = []
    let lock = NSLock()

    init(_ cards: [String: ExtractedCard]) { self.cards = cards }

    func extract(image: ImagePayload, ocr: OCRResult?) async throws -> ExtractionOutput {
        let id = String(data: image.data, encoding: .utf8)!
        lock.lock(); calls.append(id); let t = transientFor; let p = permanentFor; let u = unauthorized; lock.unlock()
        if u { throw LLMError.unauthorized("bad key") }
        if t.contains(id) { throw LLMError.transient("timeout") }
        if p.contains(id) { throw LLMError.permanent("HTTP 400") }
        var usage = TokenUsage(); usage.inputTokens = 2000; usage.outputTokens = 600; usage.costUSD = 0.02
        return ExtractionOutput(card: cards[id]!, usage: usage, model: "fake")
    }
}

struct FakeOCR: OCRProvider {
    let byID: [String: OCRResult]
    func recognize(_ image: ImagePayload) async throws -> OCRResult {
        byID[String(data: image.data, encoding: .utf8)!] ?? OCRResult(engine: "fake", lines: [])
    }
}

actor FakeImages: ImageStore {
    var deleted: Set<String> = []
    func load(_ photoID: String) async throws -> ImagePayload { ImagePayload(data: Data(photoID.utf8)) }
    func delete(_ photoID: String) async { deleted.insert(photoID) }
}

struct FakeVerifier: FieldVerifier {
    let answer: (String, [String]) -> VerifierAnswer
    func verify(fieldLabel: String, candidates: [String], images: [ImagePayload], ocrHint: [String]) async throws -> VerifierAnswer {
        answer(fieldLabel, candidates)
    }
}
