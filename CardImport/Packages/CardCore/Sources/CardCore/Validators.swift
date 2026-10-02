import Foundation

public struct ValidationIssue: Codable, Hashable, Sendable {
    public var code: String
    public var detail: String
    /// Multiplicative effect on confidence (1 = neutral, < 1 penalty).
    public var factor: Double

    public init(_ code: String, _ detail: String = "", factor: Double) {
        self.code = code; self.detail = detail; self.factor = factor
    }
}

// MARK: - Email

public enum EmailValidator {
    static let knownTLDs: Set<String> = [
        "com", "net", "org", "edu", "gov", "biz", "info", "io", "co", "ai", "app", "dev", "me", "tv", "cc",
        "asia", "global", "group", "tech", "shop", "store", "online", "site", "xyz", "pro", "mobi", "name",
        "int", "mil", "jobs", "travel", "food", "foods", "solutions", "company", "consulting", "trade",
    ]
    static let freeMailTypos: [String: String] = [
        "gmial.com": "gmail.com", "gmai.com": "gmail.com", "gmal.com": "gmail.com", "gmall.com": "gmail.com",
        "gmail.co": "gmail.com", "hotmial.com": "hotmail.com", "hotmai.com": "hotmail.com",
        "yahoo.co": "yahoo.com", "yaho.com": "yahoo.com", "outlok.com": "outlook.com", "icloud.co": "icloud.com",
        "l63.com": "163.com", "i63.com": "163.com", "qq.corn": "qq.com", "gmail.corn": "gmail.com",
    ]
    public static let freeMailDomains: Set<String> = [
        "gmail.com", "hotmail.com", "outlook.com", "yahoo.com", "yahoo.com.tw", "yahoo.com.hk", "icloud.com",
        "me.com", "live.com", "msn.com", "qq.com", "163.com", "126.com", "sina.com", "hinet.net", "msa.hinet.net",
        "rogers.com", "bell.net", "sympatico.ca", "shaw.ca", "aol.com", "protonmail.com", "proton.me",
    ]

    /// Repairs typical OCR damage: spaces, full-width chars, comma for dot, trailing punctuation, ".corn".
    public static func repair(_ raw: String) -> String {
        var s = TextNorm.nfkc(raw).lowercased()
        s = s.replacingOccurrences(of: "mailto:", with: "")
        s = s.replacingOccurrences(of: "e-mail:", with: "").replacingOccurrences(of: "email:", with: "")
        s = s.replacingOccurrences(of: "e:", with: "", options: .anchored)
        s = s.filter { !$0.isWhitespace }
        s = s.replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
        s = s.replacingOccurrences(of: "＠", with: "@").replacingOccurrences(of: "(at)", with: "@").replacingOccurrences(of: "[at]", with: "@")
        while let l = s.last, ".;:)>]".contains(l) { s.removeLast() }
        while let f = s.first, "(<[:".contains(f) { s.removeFirst() }
        if s.hasSuffix(".corn") { s = String(s.dropLast(5)) + ".com" }
        if s.hasSuffix(".c0m") { s = String(s.dropLast(4)) + ".com" }
        if let at = s.firstIndex(of: "@") {
            let domain = String(s[s.index(after: at)...])
            if let fixed = freeMailTypos[domain] { s = String(s[...at]) + fixed }
        }
        return s
    }

    public static func domain(of email: String) -> String? {
        guard let at = email.lastIndex(of: "@") else { return nil }
        let d = String(email[email.index(after: at)...]).lowercased()
        return d.isEmpty ? nil : d
    }

    public static func isSyntacticallyValid(_ s: String) -> Bool {
        let pattern = #"^[a-z0-9!#$%&'*+/=?^_`{|}~.-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$"#
        guard s.range(of: pattern, options: .regularExpression) != nil else { return false }
        if s.contains("..") || s.hasPrefix(".") || s.contains(".@") { return false }
        return true
    }

    public static func hasPlausibleTLD(_ s: String) -> Bool {
        guard let d = domain(of: s), let tld = d.split(separator: ".").last else { return false }
        let t = String(tld)
        if knownTLDs.contains(t) { return true }
        return t.count == 2 && t.allSatisfy { $0.isLetter }
    }

    public static func validate(_ email: String, siblingDomains: Set<String>) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !isSyntacticallyValid(email) { issues.append(.init("email_syntax", email, factor: 0.3)) }
        else if !hasPlausibleTLD(email) { issues.append(.init("email_tld", email, factor: 0.6)) }
        if let d = domain(of: email), !freeMailDomains.contains(d), !siblingDomains.isEmpty {
            let base = DomainUtil.registrable(d)
            let siblings = Set(siblingDomains.map(DomainUtil.registrable))
            if siblings.contains(base) {
                issues.append(.init("email_domain_matches_website", d, factor: 1.08))
            } else if siblings.contains(where: { TextNorm.editDistance($0, base) <= 2 }) {
                // e.g. abcfoods.com vs abcfood5.com — one of them is probably misread.
                issues.append(.init("email_domain_near_miss", d, factor: 0.55))
            }
        }
        return issues
    }
}

public enum DomainUtil {
    static let secondLevel: Set<String> = ["com", "co", "net", "org", "gov", "edu", "ac"]

    public static func host(fromURL raw: String) -> String? {
        var s = TextNorm.nfkc(raw).lowercased().filter { !$0.isWhitespace }
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        s = s.replacingOccurrences(of: ",", with: ".")
        while let l = s.last, ".;:".contains(l) { s.removeLast() }
        return s.contains(".") ? s : nil
    }

    /// "mail.abcfoods.com.tw" → "abcfoods.com.tw".
    public static func registrable(_ host: String) -> String {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        guard parts.count > 2 else { return parts.joined(separator: ".") }
        let last = parts[parts.count - 1], second = parts[parts.count - 2]
        if last.count == 2 && secondLevel.contains(second) { return parts.suffix(3).joined(separator: ".") }
        return parts.suffix(2).joined(separator: ".")
    }

    /// The distinctive label ("abcfoods") used to compare with company names.
    public static func label(_ host: String) -> String {
        let reg = registrable(host)
        return String(reg.split(separator: ".").first ?? Substring(reg))
    }

    public static func isPlausibleURL(_ raw: String) -> Bool {
        guard let h = host(fromURL: raw) else { return false }
        return h.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil
    }
}

// MARK: - Addresses

public enum AddressValidator {
    static let caProvinces: [String: String] = [
        "on": "ON", "ontario": "ON", "qc": "QC", "quebec": "QC", "québec": "QC", "bc": "BC", "british columbia": "BC",
        "ab": "AB", "alberta": "AB", "mb": "MB", "manitoba": "MB", "sk": "SK", "saskatchewan": "SK", "ns": "NS",
        "nova scotia": "NS", "nb": "NB", "new brunswick": "NB", "nl": "NL", "newfoundland and labrador": "NL",
        "pe": "PE", "prince edward island": "PE", "yt": "YT", "nt": "NT", "nu": "NU",
    ]
    static let usStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA",
        "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK",
        "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC",
    ]
    static let twCities = ["台北", "臺北", "新北", "桃園", "台中", "臺中", "台南", "臺南", "高雄", "基隆", "新竹", "苗栗", "彰化",
                           "南投", "雲林", "嘉義", "屏東", "宜蘭", "花蓮", "台東", "臺東", "澎湖", "金門", "連江", "taipei",
                           "new taipei", "taoyuan", "taichung", "tainan", "kaohsiung", "hsinchu", "keelung"]
    static let cnCities = ["北京", "上海", "广州", "廣州", "深圳", "天津", "重庆", "重慶", "杭州", "苏州", "蘇州", "南京", "成都", "武汉",
                           "武漢", "厦门", "廈門", "青岛", "青島", "宁波", "寧波", "东莞", "東莞", "佛山", "beijing", "shanghai",
                           "guangzhou", "shenzhen", "hangzhou", "suzhou", "xiamen"]

    /// ISO alpha-2 inferred from the parts, or nil.
    public static func inferCountry(_ a: ExtractedAddress) -> String? {
        let country = TextNorm.loose(a.country ?? "")
        let map: [(String, String)] = [
            ("canada", "CA"), ("加拿大", "CA"), ("united states", "US"), ("usa", "US"), ("u.s.a", "US"), ("美國", "US"), ("美国", "US"),
            ("taiwan", "TW"), ("台灣", "TW"), ("臺灣", "TW"), ("中華民國", "TW"), ("r.o.c", "TW"), ("china", "CN"), ("中国", "CN"),
            ("中國", "CN"), ("p.r.c", "CN"), ("hong kong", "HK"), ("香港", "HK"), ("macau", "MO"), ("澳門", "MO"), ("singapore", "SG"),
            ("新加坡", "SG"), ("japan", "JP"), ("日本", "JP"), ("korea", "KR"), ("united kingdom", "GB"), ("uk", "GB"), ("australia", "AU"),
        ]
        for (k, v) in map where country == k || country.contains(k) { return v }
        if country.count == 2 { return country.uppercased() == "UK" ? "GB" : country.uppercased() }
        let pc = TextNorm.nfkc(a.postalCode ?? "").uppercased()
        if pc.range(of: #"^[A-Z]\d[A-Z] ?\d[A-Z]\d$"#, options: .regularExpression) != nil { return "CA" }
        let region = TextNorm.loose(a.region ?? "")
        if caProvinces[region] != nil { return "CA" }
        if usStates.contains(region.uppercased()) && pc.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil { return "US" }
        let all = TextNorm.loose([a.city, a.region, a.street, a.formatted].compactMap { $0 }.joined(separator: " "))
        if twCities.contains(where: { all.contains($0) }) { return "TW" }
        if cnCities.contains(where: { all.contains($0) }) || all.contains("省") || all.contains("自治区") { return "CN" }
        if all.contains("hong kong") || all.contains("kowloon") || all.contains("九龍") || all.contains("九龙") { return "HK" }
        return nil
    }

    public static func validate(_ a: ExtractedAddress) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let country = inferCountry(a)
        let pc = TextNorm.nfkc(a.postalCode ?? "").uppercased()
        if !pc.isEmpty {
            switch country {
            case "CA":
                if pc.range(of: #"^[A-Z]\d[A-Z] ?\d[A-Z]\d$"#, options: .regularExpression) == nil {
                    issues.append(.init("postal_code_format", pc, factor: 0.6))
                }
            case "US":
                if pc.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) == nil {
                    issues.append(.init("postal_code_format", pc, factor: 0.6))
                }
            case "TW":
                if pc.range(of: #"^\d{3}(\d{2,3})?$"#, options: .regularExpression) == nil {
                    issues.append(.init("postal_code_format", pc, factor: 0.6))
                }
            case "CN":
                if pc.range(of: #"^\d{6}$"#, options: .regularExpression) == nil {
                    issues.append(.init("postal_code_format", pc, factor: 0.6))
                }
            default: break
            }
        }
        if (a.street ?? "").isEmpty && (a.city ?? "").isEmpty { issues.append(.init("address_incomplete", factor: 0.7)) }
        return issues
    }

    /// Canadian postal codes: repair O/0 and I/1 confusions by position (A1A 1A1).
    public static func repairCanadianPostalCode(_ raw: String) -> String {
        let s = TextNorm.nfkc(raw).uppercased().filter { !$0.isWhitespace }
        guard s.count == 6 else { return TextNorm.nfkc(raw).uppercased() }
        let toDigit: [Character: Character] = ["O": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2", "G": "6"]
        let toLetter: [Character: Character] = ["0": "O", "1": "I", "5": "S", "8": "B", "2": "Z", "6": "G"]
        var out: [Character] = []
        for (i, ch) in s.enumerated() {
            if i % 2 == 0 { out.append(toLetter[ch] ?? ch) } else { out.append(toDigit[ch] ?? ch) }
        }
        let fixed = String(out)
        return String(fixed.prefix(3)) + " " + String(fixed.suffix(3))
    }

    public static func canonicalRegion(_ region: String?, country: String?) -> String? {
        guard let r = region, !r.isEmpty else { return nil }
        if country == "CA", let code = caProvinces[TextNorm.loose(r)] { return code }
        return TextNorm.nfkc(r)
    }
}
