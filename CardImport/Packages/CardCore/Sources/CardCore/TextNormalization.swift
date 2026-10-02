import Foundation

public enum TextNorm {
    /// NFKC fold (full-width → half-width, compatibility forms), trims whitespace.
    public static func nfkc(_ s: String) -> String {
        s.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased, NFKC, collapsed whitespace, diacritics removed.
    public static func loose(_ s: String) -> String {
        let folded = nfkc(s).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Only letters and digits (any script), lowercased.
    public static func alnum(_ s: String) -> String {
        String(loose(s).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    public static func digits(_ s: String) -> String {
        String(nfkc(s).unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.map(Character.init))
    }

    public static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0xF900...0xFAFF, 0x2F800...0x2FA1F:
            return true
        default:
            return false
        }
    }

    public static func containsCJK(_ s: String) -> Bool { s.unicodeScalars.contains(where: isCJK) }

    public static func cjkCount(_ s: String) -> Int { s.unicodeScalars.filter(isCJK).count }

    public static func isMostlyLatin(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let latin = letters.filter { $0.value < 0x250 }
        return Double(latin.count) / Double(letters.count) > 0.8
    }

    /// Traditional → Simplified (ICU). Used so that 陳 and 陈 compare equal.
    public static func toSimplified(_ s: String) -> String {
        s.applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) ?? s
    }

    /// Hanyu pinyin without tones, lowercase, space separated. "王大明" → "wang da ming".
    public static func pinyin(_ s: String) -> String {
        let latin = s.applyingTransform(.toLatin, reverse: false) ?? s
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return plain.lowercased()
    }

    /// Levenshtein distance over Characters.
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Similarity in [0,1] based on edit distance of the loose forms.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = alnum(a), y = alnum(b)
        if x.isEmpty && y.isEmpty { return 1 }
        let d = editDistance(x, y)
        return 1 - Double(d) / Double(max(x.count, y.count))
    }

    /// Maps characters that OCR commonly confuses onto one canonical form
    /// (O→0, l/I/|→1, S→5, B→8, Z→2, G→6, rn→m). Used to compare digits-ish strings.
    public static func confusableFold(_ s: String) -> String {
        var t = loose(s).replacingOccurrences(of: "rn", with: "m")
        let map: [Character: Character] = ["o": "0", "l": "1", "i": "1", "|": "1", "s": "5", "b": "8", "z": "2", "g": "6", "q": "9"]
        t = String(t.map { map[$0] ?? $0 })
        return t
    }

    public static func tokens(_ s: String) -> [String] {
        loose(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !$0.isEmpty }
    }
}
