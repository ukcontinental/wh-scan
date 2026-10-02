import Foundation

/// How strongly the independent on-device OCR transcript supports a value read by the AI model.
public enum OCRSupport: String, Codable, Sendable {
    case strong      // value (normalised) appears verbatim
    case partial     // appears after folding OCR-confusable characters, or most tokens appear
    case conflict    // OCR read a near-identical but different value (one digit / letter off)
    case none        // OCR read the area but the value is not there
    case unavailable // OCR missing / unreliable for this script
}

public enum FieldKind: String, Codable, Sendable {
    case personName, company, jobTitle, department, phone, email, website, address, social
}

public enum OCRCrossCheck {
    /// Is the OCR transcript usable for verifying this value at all?
    static func usable(_ ocr: OCRResult?, forCJK: Bool) -> Bool {
        guard let ocr, !ocr.lines.isEmpty else { return false }
        let text = ocr.fullText
        if forCJK {
            // Require the OCR to have actually produced CJK text.
            return TextNorm.cjkCount(text) >= 2
        }
        return text.count >= 8
    }

    public static func support(value: String, kind: FieldKind, ocr: OCRResult?) -> OCRSupport {
        let isCJK = TextNorm.containsCJK(value)
        guard usable(ocr, forCJK: isCJK), let ocr else { return .unavailable }
        let lines = ocr.lines.map(\.text)
        let joined = lines.joined(separator: " ")
        switch kind {
        case .phone:
            let target = TextNorm.digits(value)
            guard target.count >= 6 else { return .unavailable }
            // Compare the national significant part so "+1 416…" matches "416…".
            let tail = String(target.suffix(min(target.count, 9)))
            let ocrDigitsPerLine = lines.map { TextNorm.digits($0) }
            if ocrDigitsPerLine.contains(where: { $0.contains(tail) }) || TextNorm.digits(joined).contains(tail) { return .strong }
            let foldedTail = TextNorm.confusableFold(tail)
            if lines.contains(where: { TextNorm.confusableFold($0).filter(\.isNumber).contains(foldedTail) }) { return .partial }
            // One digit off somewhere in the transcript: one of the two readers is wrong.
            for d in ocrDigitsPerLine where d.count >= tail.count {
                let chars = Array(d)
                for start in 0...(chars.count - tail.count) {
                    if TextNorm.editDistance(String(chars[start..<(start + tail.count)]), tail) <= 2 { return .conflict }
                }
            }
            return .none
        case .address:
            // Addresses span several printed lines and OCR line order varies: compare token coverage.
            let tokens = TextNorm.tokens(value).filter { $0.count >= 2 || $0.allSatisfy(\.isNumber) }
            guard !tokens.isEmpty else { return .unavailable }
            let o = TextNorm.alnum(joined)
            let hits = tokens.filter { o.contains(TextNorm.alnum($0)) }.count
            let ratio = Double(hits) / Double(tokens.count)
            if ratio >= 0.9 { return .strong }
            if ratio >= 0.6 { return .partial }
            return .none
        case .email, .website:
            let v = TextNorm.alnum(value)
            let o = TextNorm.alnum(joined)
            if o.contains(v) { return .strong }
            if TextNorm.confusableFold(o).contains(TextNorm.confusableFold(v)) { return .partial }
            // Near miss (edit distance over a sliding window): the two readers disagree on a character.
            if bestWindowSimilarity(v, in: o) >= 0.8 { return .conflict }
            return .none
        default:
            let v = TextNorm.alnum(value)
            guard !v.isEmpty else { return .unavailable }
            let o = TextNorm.alnum(joined)
            if o.contains(v) { return .strong }
            let tokens = TextNorm.tokens(value)
            if tokens.count >= 2 {
                let hits = tokens.filter { o.contains(TextNorm.alnum($0)) }.count
                if Double(hits) / Double(tokens.count) >= 0.66 { return .partial }
            }
            if bestWindowSimilarity(v, in: o) >= 0.8 { return .partial }
            return .none
        }
    }

    static func bestWindowSimilarity(_ needle: String, in hay: String) -> Double {
        let n = Array(needle), h = Array(hay)
        guard !n.isEmpty, h.count >= n.count else { return h.isEmpty ? 0 : TextNorm.similarity(needle, hay) }
        var best = 0.0
        let w = n.count
        var i = 0
        // Step by 1 but cap work for very long transcripts.
        let step = max(1, (h.count - w) / 400)
        while i + w <= h.count {
            let window = String(h[i..<(i + w)])
            let d = TextNorm.editDistance(needle, window)
            best = max(best, 1 - Double(d) / Double(w))
            if best == 1 { break }
            i += step
        }
        return best
    }
}

/// Evidence-combination in log-odds space. Each signal shifts the logit by a fixed weight;
/// weights were chosen conservatively and are re-calibrated by the benchmark (see docs).
public enum OCRReliability {
    /// Fraction of the model's confident short values (names, phones, emails, websites) that the OCR also read.
    public static func estimate(card: ExtractedCard, ocr: OCRResult?) -> Double {
        guard let ocr, !ocr.lines.isEmpty else { return 0 }
        var checks: [(String, FieldKind)] = []
        for f in [card.name.given, card.name.family, card.name.cjkFull, card.company, card.companyCjk, card.jobTitle] {
            if let f, f.confidence >= 0.9 { checks.append((f.value, .personName)) }
        }
        for p in card.phones where p.confidence >= 0.9 { checks.append((p.number, .phone)) }
        for e in card.emails where e.confidence >= 0.9 { checks.append((e.address, .email)) }
        for w in card.websites where w.confidence >= 0.9 { checks.append((w.url, .website)) }
        var score = 0.0, n = 0.0
        for (v, k) in checks {
            switch OCRCrossCheck.support(value: v, kind: k, ocr: ocr) {
            case .strong: score += 1; n += 1
            case .partial: score += 0.6; n += 1
            case .conflict: score += 0.3; n += 1
            case .none: n += 1
            case .unavailable: break
            }
        }
        guard n >= 3 else { return 0.5 }
        return score / n
    }
}

public struct ConfidenceModel: Codable, Sendable {
    public var ocrStrong = 1.2
    public var ocrPartial = 0.2
    public var ocrConflict = -2.5
    public var ocrNone = -1.6
    public var crossSideAgree = 1.5
    public var crossSideConflict = -2.0
    public var secondOpinionAgree = 2.0
    public var secondOpinionDisagree = -2.5
    public var crossScriptNameMatch = 1.0
    public var maxConfidence = 0.995

    public init() {}

    public static func logit(_ p: Double) -> Double {
        let q = min(max(p, 0.001), 0.999)
        return log(q / (1 - q))
    }

    public static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    public func adjust(_ p: Double, deltas: [Double]) -> Double {
        min(Self.sigmoid(Self.logit(p) + deltas.reduce(0, +)), maxConfidence)
    }

    /// `reliability` (0…1) says how trustworthy this photo's OCR transcript is, measured by how often it agrees
    /// with the model on the fields the model is sure about. A weak OCR (stylised fonts, CJK, low resolution)
    /// that misses a value is weak evidence; a good OCR that misses it is strong evidence.
    public func delta(for support: OCRSupport, reliability: Double = 1) -> Double {
        let r = min(max(reliability, 0), 1)
        switch support {
        case .strong: return ocrStrong
        case .partial: return ocrPartial
        case .conflict: return ocrConflict * (0.4 + 0.6 * r)
        case .none: return ocrNone * r * r
        case .unavailable: return 0
        }
    }

    /// Validator factor (multiplicative, 1 = neutral) → logit delta.
    public func delta(forFactor f: Double) -> Double {
        guard f != 1 else { return 0 }
        return f < 1 ? log(max(f, 0.01)) * 2.2 : log(f) * 4
    }
}
