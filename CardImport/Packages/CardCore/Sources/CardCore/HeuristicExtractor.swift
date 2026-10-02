import Foundation

/// "Option A" reader: on-device OCR + rules, no AI model. Free, private and offline, used
/// (1) as the benchmark baseline and (2) as the offline fallback in the app. Its confidences are
/// deliberately modest because rule-based field classification is the weak point of this approach.
public struct HeuristicExtractor: CardExtractor {
    public var defaultRegion: String
    public init(defaultRegion: String = "CA") { self.defaultRegion = defaultRegion }

    public func extract(image: ImagePayload, ocr: OCRResult?) async throws -> ExtractionOutput {
        ExtractionOutput(card: extract(ocr: ocr ?? OCRResult(engine: "none", lines: [])), model: "heuristic")
    }

    static let emailRE = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+\s?@\s?[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
    static let urlRE = try! NSRegularExpression(pattern: #"(?i)\b((?:https?://)?(?:www\.)?[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.(?:com|net|org|ca|tw|cn|hk|io|co|us|biz|info|com\.tw|com\.cn|com\.hk)(?:/[^\s]*)?)"#)
    static let phoneRE = try! NSRegularExpression(pattern: #"(\+?\(?\d[\d\s().\-]{6,}\d)(\s*(?:ext\.?|x|分機|转|轉|#)\s*\d{1,5})?"#)
    static let streetWords = ["street", " st ", " st.", "avenue", " ave", "road", " rd", "blvd", "boulevard", "drive", " dr", "suite",
                              "unit", "floor", " fl", "way", "lane", "court", "parkway", "highway", "place", "square", "building",
                              "路", "街", "號", "号", "樓", "楼", "段", "巷", "弄", "區", "区", "大道", "大廈", "大厦", "室"]

    public func extract(ocr: OCRResult) -> ExtractedCard {
        var card = ExtractedCard()
        var used = Set<Int>()
        let lines = ocr.lines.map { OCRLine(text: TextNorm.nfkc($0.text), confidence: $0.confidence, box: $0.box) }
            .filter { !$0.text.isEmpty }
        func conf(_ l: OCRLine, _ base: Double) -> Double { min(0.97, base * (0.55 + 0.45 * max(0, min(1, l.confidence)))) }

        for (i, l) in lines.enumerated() {
            let t = l.text
            let ns = NSRange(t.startIndex..., in: t)
            var hit = false
            for m in Self.emailRE.matches(in: t, range: ns) {
                if let r = Range(m.range, in: t) {
                    card.emails.append(ExtractedEmail(address: String(t[r]).replacingOccurrences(of: " ", with: ""), confidence: conf(l, 0.93), sourceText: t))
                    hit = true
                }
            }
            if !hit {
                for m in Self.urlRE.matches(in: t, range: ns) {
                    if let r = Range(m.range(at: 1), in: t) {
                        card.websites.append(ExtractedWebsite(url: String(t[r]).lowercased(), confidence: conf(l, 0.9)))
                        hit = true
                    }
                }
            }
            let digitCount = t.filter(\.isNumber).count
            if digitCount >= 7 && !t.contains("@") {
                // A line may hold several numbers: "T 416.555.0137 | F 416.555.0199".
                let segments = t.components(separatedBy: CharacterSet(charactersIn: "|／/;、")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for seg in segments {
                    let sns = NSRange(seg.startIndex..., in: seg)
                    for m in Self.phoneRE.matches(in: seg, range: sns) {
                        guard let r = Range(m.range(at: 1), in: seg) else { continue }
                        let num = String(seg[r])
                        if TextNorm.digits(num).count < 7 { continue }
                        // Postal codes / years are not phones.
                        if looksLikeAddress(seg) && TextNorm.digits(num).count < 9 { continue }
                        var ext: String? = nil
                        if let er = Range(m.range(at: 2), in: seg) { ext = TextNorm.digits(String(seg[er])) }
                        let label = PhoneNormalizer.kindFromLabel(seg)
                        card.phones.append(ExtractedPhone(kind: label ?? .work, number: num.trimmingCharacters(in: .whitespaces), extension: ext,
                                                          confidence: conf(l, label == nil ? 0.85 : 0.92), sourceText: seg))
                        hit = true
                    }
                }
            }
            if hit { used.insert(i) }
        }

        // Addresses: consecutive address-looking lines.
        var addrLines: [String] = []
        var addrConf = 1.0
        for (i, l) in lines.enumerated() where !used.contains(i) && looksLikeAddress(l.text) {
            addrLines.append(l.text); addrConf = min(addrConf, l.confidence); used.insert(i)
        }
        if !addrLines.isEmpty {
            let formatted = addrLines.joined(separator: ", ")
            card.addresses.append(parseAddress(formatted, confidence: 0.7 * (0.6 + 0.4 * addrConf)))
        }

        // Company, title, name among the remaining lines.
        var remaining = lines.enumerated().filter { !used.contains($0.offset) }
        if let (i, l) = remaining.first(where: { CompanyUtil.hasLegalSuffix($0.element.text) }).map({ ($0.offset, $0.element) }) {
            if TextNorm.containsCJK(l.text) { card.companyCjk = FieldValue(l.text, confidence: conf(l, 0.85)) }
            else { card.company = FieldValue(l.text, confidence: conf(l, 0.85)) }
            used.insert(i)
        }
        remaining = lines.enumerated().filter { !used.contains($0.offset) }
        for (i, l) in remaining.map({ ($0.offset, $0.element) }) {
            let lt = TextNorm.loose(l.text)
            if CardScorer.titleKeywords.contains(where: { lt.contains($0) }) && l.text.count <= 40 {
                if TextNorm.containsCJK(l.text) { if card.jobTitleCjk == nil { card.jobTitleCjk = FieldValue(l.text, confidence: conf(l, 0.75)); used.insert(i) } }
                else if card.jobTitle == nil { card.jobTitle = FieldValue(l.text, confidence: conf(l, 0.75)); used.insert(i) }
            }
        }
        remaining = lines.enumerated().filter { !used.contains($0.offset) }
        // Name: prefer the tallest name-shaped line.
        let nameCandidates = remaining.filter { NameUtil.looksLikePersonName($0.element.text) && !CompanyUtil.hasLegalSuffix($0.element.text) }
            .sorted { ($0.element.box?[3] ?? 0) > ($1.element.box?[3] ?? 0) }
        for c in nameCandidates {
            let t = c.element.text
            if TextNorm.containsCJK(t) {
                if card.name.cjkFull == nil { card.name.cjkFull = FieldValue(t.filter { !$0.isWhitespace }, confidence: conf(c.element, 0.8)); used.insert(c.offset) }
            } else if card.name.given == nil, TextNorm.isMostlyLatin(t) {
                let words = t.split(separator: " ").map(String.init)
                guard words.count >= 2, words.allSatisfy({ $0.first?.isUppercase ?? false }) else { continue }
                let titled = words.map { $0.count > 1 && $0 == $0.uppercased() ? $0.prefix(1) + $0.dropFirst().lowercased() : Substring($0) }.map(String.init)
                card.name.given = FieldValue(titled.dropLast().joined(separator: " "), confidence: conf(c.element, 0.75))
                card.name.family = FieldValue(titled.last!, confidence: conf(c.element, 0.75))
                used.insert(c.offset)
            }
        }
        // Company fallback: a remaining line that matches the web/email domain.
        if card.company == nil && card.companyCjk == nil {
            let domains = card.websites.compactMap { DomainUtil.host(fromURL: $0.url) } + card.emails.compactMap { EmailValidator.domain(of: $0.address) }
            for (i, l) in lines.enumerated() where !used.contains(i) {
                if domains.contains(where: { CompanyUtil.domainAffinity(company: l.text, domainLabel: DomainUtil.label($0)) >= 0.6 }) {
                    card.company = FieldValue(l.text, confidence: conf(l, 0.7)); used.insert(i); break
                }
            }
        }
        card.cardSide = card.name.isEmpty ? .back : .front
        card.languageHint = TextNorm.containsCJK(ocr.fullText) ? (TextNorm.isMostlyLatin(ocr.fullText) ? ["en", "zh-Hant"] : ["zh-Hant"]) : ["en"]
        card.evidence = Evidence(ignoredText: lines.enumerated().filter { !used.contains($0.offset) }.map(\.element.text),
                                 overallConfidence: 0.6)
        return card
    }

    func looksLikeAddress(_ t: String) -> Bool {
        let l = " " + TextNorm.loose(t) + " "
        if l.range(of: #"[a-z]\d[a-z] ?\d[a-z]\d"#, options: .regularExpression) != nil { return true }   // CA postal
        if l.range(of: #"\b(on|bc|qc|ab|ny|ca|wa|tx)\b,? *\d{5}|\b[a-z]{2} \d{5}(-\d{4})?\b"#, options: .regularExpression) != nil { return true }
        let hasDigit = l.contains(where: \.isNumber)
        return hasDigit && Self.streetWords.contains(where: { l.contains($0) }) && !l.contains("@")
    }

    func parseAddress(_ s: String, confidence: Double) -> ExtractedAddress {
        var a = ExtractedAddress(formatted: s, confidence: confidence)
        if let r = s.range(of: #"[A-Za-z]\d[A-Za-z] ?\d[A-Za-z]\d"#, options: .regularExpression) {
            a.postalCode = String(s[r]).uppercased(); a.country = "Canada"
        } else if let r = s.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) {
            a.postalCode = String(s[r])
        }
        let parts = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count >= 2 { a.street = parts[0]; a.city = parts[1].components(separatedBy: " ").first }
        else { a.street = s }
        return a
    }
}
