import Foundation

/// A phone number normalised to E.164 plus metadata. Pure Swift, no libphonenumber dependency;
/// covers the regions this product targets (NANP, Taiwan, Mainland China, Hong Kong, Macau,
/// Singapore, Japan, Korea, UK, Australia) and keeps anything else as "+<digits>" when a country
/// code was printed.
public struct NormalizedPhone: Codable, Hashable, Sendable {
    public var e164: String
    public var region: String?
    public var extensionNumber: String?
    public var isValid: Bool
    /// Number-plan derived type when the plan tells us (TW 09x, CN 1x, HK 5/6/9 = mobile).
    public var planType: PlanType

    public enum PlanType: String, Codable, Sendable { case mobile, fixed, unknown }
}

public enum PhoneNormalizer {
    static let countryCodes: [String: String] = [
        "1": "US", "886": "TW", "86": "CN", "852": "HK", "853": "MO", "65": "SG", "81": "JP", "82": "KR",
        "44": "GB", "61": "AU", "60": "MY", "66": "TH", "84": "VN", "63": "PH", "49": "DE", "33": "FR",
    ]
    static let regionToCode: [String: String] = [
        "US": "1", "CA": "1", "TW": "886", "CN": "86", "HK": "852", "MO": "853", "SG": "65", "JP": "81",
        "KR": "82", "GB": "44", "UK": "44", "AU": "61", "MY": "60", "TH": "66", "VN": "84", "PH": "63",
        "DE": "49", "FR": "33",
    ]

    /// Splits "416-555-0137 ext. 204" / "x204" / "分機 204" / "轉204" / "#204".
    public static func splitExtension(_ raw: String) -> (String, String?) {
        let s = TextNorm.nfkc(raw)
        let patterns = [
            #"(?i)\s*(?:ext\.?|extension|x|分機|分机|轉|转|内线|內線)\s*[:：.]?\s*(\d{1,6})\s*$"#,
            #"\s*#\s*(\d{1,6})\s*$"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range, in: s), let er = Range(m.range(at: 1), in: s) {
                return (String(s[s.startIndex..<r.lowerBound]), String(s[er]))
            }
        }
        return (s, nil)
    }

    /// Normalises a printed number. `regionHint` is ISO alpha-2 inferred from the card
    /// (printed country code, address, other phones) or the device default.
    public static func normalize(_ raw: String, regionHint: String?, defaultRegion: String = "CA",
                                 extensionHint: String? = nil) -> NormalizedPhone? {
        let (body, ext0) = splitExtension(raw)
        let ext = extensionHint ?? ext0
        let trimmed = TextNorm.nfkc(body)
        var digits = TextNorm.digits(trimmed)
        guard digits.count >= 6 else { return nil }
        let hasPlus = trimmed.contains("+") || trimmed.hasPrefix("00") && digits.hasPrefix("00")
        if trimmed.hasPrefix("00") { digits.removeFirst(2) }

        // Explicit international form.
        if hasPlus || trimmed.hasPrefix("00") {
            for len in [3, 2, 1] where digits.count > len {
                let cc = String(digits.prefix(len))
                if let region = countryCodes[cc] {
                    var national = String(digits.dropFirst(len))
                    // "+886 (0)2-2345-6789" — drop trunk 0 printed after a country code.
                    if national.hasPrefix("0") && cc != "39" { national.removeFirst() }
                    let reg = (cc == "1") ? nanpRegion(regionHint) : region
                    return build(cc: cc, national: national, region: reg, ext: ext)
                }
            }
            return NormalizedPhone(e164: "+" + digits, region: nil, extensionNumber: ext,
                                   isValid: digits.count >= 8 && digits.count <= 15, planType: .unknown)
        }

        // Country code printed without "+", e.g. "(852) 2560 7397", "886-2-2345-6789", "86 21 6123 4567".
        let groups = trimmed.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { !$0.isEmpty }
        if let first = groups.first, groups.count >= 2, first != "1", let region = countryCodes[first] {
            var national = String(digits.dropFirst(first.count))
            if national.hasPrefix("0") { national.removeFirst() }
            let (valid, _) = validate(cc: first, national: national)
            if valid { return build(cc: first, national: national, region: region, ext: ext) }
        }

        // National form: infer the country from the hint and the shape of the number.
        let hint = (regionHint ?? defaultRegion).uppercased()
        if let guess = guessRegion(nationalDigits: digits, hint: hint) {
            var national = digits
            if guess.cc != "1" && national.hasPrefix("0") { national.removeFirst() }
            if guess.cc == "1" && national.count == 11 && national.hasPrefix("1") { national.removeFirst() }
            return build(cc: guess.cc, national: national, region: guess.region, ext: ext)
        }
        let cc = regionToCode[hint] ?? "1"
        var national = digits
        if national.hasPrefix("0") { national.removeFirst() }
        return NormalizedPhone(e164: "+" + cc + national, region: hint, extensionNumber: ext, isValid: false, planType: .unknown)
    }

    private static func nanpRegion(_ hint: String?) -> String {
        if let h = hint?.uppercased(), h == "CA" || h == "US" { return h }
        return "US"
    }

    private static func guessRegion(nationalDigits d: String, hint: String) -> (cc: String, region: String)? {
        // Shapes that are unambiguous regardless of hint.
        if d.count == 10, d.hasPrefix("09") { return ("886", "TW") }                       // TW mobile
        if d.count == 11, d.hasPrefix("1"), let c = d.dropFirst().first, "3456789".contains(c), hint != "US" && hint != "CA" {
            return ("86", "CN")                                                            // CN mobile
        }
        switch hint {
        case "US", "CA":
            if d.count == 10 || (d.count == 11 && d.hasPrefix("1")) { return ("1", hint) }
        case "TW":
            if d.hasPrefix("0") && (d.count == 9 || d.count == 10) { return ("886", "TW") }
            if d.count == 8 || d.count == 7 { return nil }
        case "CN":
            if d.hasPrefix("0") && (d.count >= 10 && d.count <= 12) { return ("86", "CN") }
            if d.count == 11 && d.hasPrefix("1") { return ("86", "CN") }
        case "HK", "MO", "SG":
            if d.count == 8 { return (regionToCode[hint]!, hint) }
        default:
            if let cc = regionToCode[hint] { return (cc, hint) }
        }
        // Fall back on shape alone.
        if d.count == 10, let f = d.first, "23456789".contains(f) { return ("1", hint == "CA" ? "CA" : "US") }
        if d.count == 11 && d.hasPrefix("1") { return ("1", hint == "CA" ? "CA" : "US") }
        if d.hasPrefix("0") && (d.count == 9 || d.count == 10) && hint == "TW" { return ("886", "TW") }
        return nil
    }

    private static func build(cc: String, national: String, region: String, ext: String?) -> NormalizedPhone {
        let (valid, type) = validate(cc: cc, national: national)
        return NormalizedPhone(e164: "+" + cc + national, region: region, extensionNumber: ext, isValid: valid, planType: type)
    }

    /// Number-plan validation for the supported regions.
    static func validate(cc: String, national n: String) -> (Bool, NormalizedPhone.PlanType) {
        let chars = Array(n)
        switch cc {
        case "1":
            guard n.count == 10, let a = chars.first, let c = chars.dropFirst(3).first else { return (false, .unknown) }
            let ok = "23456789".contains(a) && "23456789".contains(c) && !(chars[1] == "1" && chars[2] == "1")
            return (ok, .unknown)
        case "886":
            if n.hasPrefix("9") { return (n.count == 9, .mobile) }
            return (n.count == 8 || n.count == 9, .fixed)
        case "86":
            if n.count == 11 && n.hasPrefix("1") && "3456789".contains(chars[1]) { return (true, .mobile) }
            if n.hasPrefix("10") { return (n.count == 10, .fixed) }          // Beijing 010-xxxxxxxx
            if n.hasPrefix("1") { return (false, .unknown) }
            return (n.count >= 9 && n.count <= 11, .fixed)
        case "852":
            guard n.count == 8, let f = chars.first else { return (false, .unknown) }
            if "5679".contains(f) { return (true, .mobile) }
            return ("23".contains(f), .fixed)
        case "853":
            return (n.count == 8, n.hasPrefix("6") ? .mobile : .fixed)
        case "65":
            return (n.count == 8, (n.hasPrefix("8") || n.hasPrefix("9")) ? .mobile : .fixed)
        case "44":
            return (n.count == 10, n.hasPrefix("7") ? .mobile : .fixed)
        case "61":
            return (n.count == 9, n.hasPrefix("4") ? .mobile : .fixed)
        case "81":
            return (n.count == 9 || n.count == 10, (n.hasPrefix("70") || n.hasPrefix("80") || n.hasPrefix("90")) ? .mobile : .fixed)
        case "82":
            return (n.count >= 8 && n.count <= 10, n.hasPrefix("10") ? .mobile : .fixed)
        default:
            return (n.count >= 6 && n.count <= 13, .unknown)
        }
    }

    /// ISO region for an E.164 number's country code ("+852…" → "HK").
    public static func region(ofE164 e164: String) -> String? {
        let d = TextNorm.digits(e164)
        for len in [3, 2, 1] where d.count > len {
            if let r = countryCodes[String(d.prefix(len))] { return r == "US" ? "CA" : r }
        }
        return nil
    }

    /// Label keywords printed next to a number → kind.
    public static func kindFromLabel(_ text: String) -> PhoneKind? {
        let t = TextNorm.loose(text)
        let fax = ["fax", "f:", "f.", "傳真", "传真", "facsimile"]
        let mobile = ["mobile", "mob", "cell", "m:", "m.", "手機", "手机", "行動", "行动", "手提", "移動", "移动", "c:"]
        let work = ["tel", "t:", "t.", "office", "direct", "phone", "p:", "電話", "电话", "直線", "直线", "辦公", "办公", "o:", "d:"]
        let main = ["main", "總機", "总机", "toll free", "toll-free", "代表號", "代表号"]
        func has(_ keys: [String]) -> Bool { keys.contains { t.contains($0) } }
        if has(fax) { return .fax }
        if has(mobile) { return .mobile }
        if has(main) { return .main }
        if has(work) { return .work }
        return nil
    }
}
