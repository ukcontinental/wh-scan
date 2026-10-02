import Foundation

public enum NameUtil {
    /// Romanisations of common Chinese surnames: Hanyu pinyin, Wade–Giles (Taiwan), Cantonese (HK),
    /// Hokkien/Teochew (SE Asia). Keys are Traditional characters; Simplified input is converted first.
    static let surnameRomanisations: [String: [String]] = [
        "王": ["wang", "wong", "ong", "heng"], "陳": ["chen", "chan", "tan", "chin", "tran"], "林": ["lin", "lam", "lim", "lum"],
        "張": ["zhang", "chang", "cheung", "chong", "teo", "cheong"], "李": ["li", "lee", "lei", "ly"],
        "黃": ["huang", "wong", "hwang", "ng", "ooi", "wee"], "吳": ["wu", "ng", "goh", "woo", "ngo"],
        "劉": ["liu", "lau", "low", "lao", "lew"], "蔡": ["cai", "tsai", "choi", "chua", "choy", "tsoi"],
        "楊": ["yang", "yeung", "young", "yeo", "yong"], "許": ["xu", "hsu", "hui", "koh", "khoo", "hu"],
        "鄭": ["zheng", "cheng", "chang", "tay", "teh", "chiang"], "謝": ["xie", "hsieh", "tse", "chia", "sia", "tse"],
        "郭": ["guo", "kuo", "kwok", "kok", "quek", "koay"], "洪": ["hong", "hung", "ang"], "曾": ["zeng", "tseng", "tsang", "chan", "tsang"],
        "周": ["zhou", "chou", "chow", "chau", "chew", "jow"], "趙": ["zhao", "chao", "chiu", "chew", "chu"],
        "何": ["he", "ho", "hoh", "hoe"], "胡": ["hu", "wu", "woo", "oh", "foo"], "高": ["gao", "kao", "ko", "koh", "kou"],
        "羅": ["luo", "lo", "law", "loh", "lor"], "梁": ["liang", "leung", "neo", "leong", "liong"],
        "宋": ["song", "sung", "soong"], "唐": ["tang", "tong"], "馬": ["ma", "mah", "beh"], "孫": ["sun", "suen", "soon", "sng"],
        "朱": ["zhu", "chu", "chue", "choo"], "徐": ["xu", "hsu", "tsui", "chee", "tsui", "zee"], "葉": ["ye", "yeh", "yip", "yap", "ip"],
        "蕭": ["xiao", "hsiao", "siu", "seow", "shaw"], "潘": ["pan", "poon", "phua", "pang"], "鄧": ["deng", "teng", "tang", "tan"],
        "范": ["fan", "huan", "pham"], "傅": ["fu", "foo", "poh"], "彭": ["peng", "pang", "phang"], "呂": ["lu", "lui", "lu", "loo", "lyu"],
        "蘇": ["su", "so", "soh", "soo"], "盧": ["lu", "lo", "lou", "loh", "lu"], "蔣": ["jiang", "chiang", "cheung", "tseung"],
        "沈": ["shen", "sham", "sim", "shum"], "姚": ["yao", "yiu"], "余": ["yu", "yee", "yue", "ee"], "杜": ["du", "tu", "to", "doo"],
        "戴": ["dai", "tai", "tay"], "夏": ["xia", "hsia", "ha"], "鍾": ["zhong", "chung", "chong"], "汪": ["wang", "wong"],
        "田": ["tian", "tien", "tin"], "任": ["ren", "jen", "yam", "yum"], "姜": ["jiang", "chiang", "keung"], "方": ["fang", "fong", "png"],
        "石": ["shi", "shih", "shek"], "廖": ["liao", "liu", "liew", "leow"], "賴": ["lai", "lye"], "邱": ["qiu", "chiu", "yau", "khoo"],
        "侯": ["hou", "hau"], "簡": ["jian", "chien", "kan", "kan"], "江": ["jiang", "chiang", "kong", "kang"], "柯": ["ke", "ko", "kuah"],
        "游": ["you", "yu", "yau", "yeo"], "詹": ["zhan", "chan", "jim"], "顏": ["yan", "yen", "ngan", "gan"], "魏": ["wei", "ngai"],
        "陸": ["lu", "luk", "loke"], "孔": ["kong", "hung"], "白": ["bai", "pai", "pak"], "崔": ["cui", "tsui", "choi"], "康": ["kang", "hong"],
        "毛": ["mao", "mo"], "邵": ["shao", "siu"], "萬": ["wan", "man"], "錢": ["qian", "chien", "chin"], "嚴": ["yan", "yen", "yim"],
        "金": ["jin", "chin", "kam", "kim"], "韓": ["han", "hon"], "董": ["dong", "tung"], "袁": ["yuan", "yuen", "woon"], "于": ["yu", "yue"],
        "歐陽": ["ouyang", "auyeung", "auyang", "owyang"], "司徒": ["situ", "szeto", "seto"], "上官": ["shangguan"],
        "諸葛": ["zhuge"], "東方": ["dongfang", "tungfang"], "皇甫": ["huangfu"], "司馬": ["sima", "szema"], "張簡": ["changchien", "zhangjian"],
        "范姜": ["fanchiang", "fanjiang"], "慕容": ["murong"], "令狐": ["linghu"], "夏侯": ["xiahou"], "公孫": ["gongsun"],
    ]

    static let compoundSurnames: Set<String> = ["歐陽", "司徒", "上官", "諸葛", "東方", "皇甫", "司馬", "張簡", "范姜", "慕容",
                                                 "令狐", "夏侯", "公孫", "尉遲", "長孫", "宇文", "欧阳", "司马", "诸葛", "张简", "长孙", "公孙"]

    static func traditionalKey(_ s: String) -> String {
        // Simplified→Traditional for lookup (ICU has no reliable S→T for names, so map the common ones).
        let sToT: [Character: Character] = ["陈": "陳", "张": "張", "黄": "黃", "吴": "吳", "刘": "劉", "杨": "楊", "许": "許",
            "郑": "鄭", "谢": "謝", "赵": "趙", "罗": "羅", "孙": "孫", "叶": "葉", "萧": "蕭", "邓": "鄧", "吕": "呂", "苏": "蘇",
            "卢": "盧", "蒋": "蔣", "钟": "鍾", "赖": "賴", "简": "簡", "颜": "顏", "陆": "陸", "钱": "錢", "严": "嚴", "韩": "韓",
            "马": "馬", "冯": "馮", "欧": "歐", "阳": "陽", "司": "司", "万": "萬"]
        return String(s.map { sToT[$0] ?? $0 })
    }

    /// Splits "王大明" → ("王", "大明"), handling compound surnames.
    public static func splitCJK(_ full: String) -> (family: String, given: String) {
        let s = TextNorm.nfkc(full).filter { !$0.isWhitespace && $0 != "·" && $0 != "・" }
        guard s.count >= 2 else { return (s, "") }
        let first2 = String(s.prefix(2))
        if s.count >= 3 && (compoundSurnames.contains(first2) || compoundSurnames.contains(traditionalKey(first2))) {
            return (first2, String(s.dropFirst(2)))
        }
        return (String(s.prefix(1)), String(s.dropFirst()))
    }

    public static func isKnownSurname(_ cjkFamily: String) -> Bool {
        let key = traditionalKey(cjkFamily)
        return surnameRomanisations[key] != nil || compoundSurnames.contains(cjkFamily)
    }

    /// All plausible romanisations of a CJK surname (pinyin from ICU + table).
    public static func romanisations(ofCJKSurname family: String) -> Set<String> {
        var out = Set(surnameRomanisations[traditionalKey(family)] ?? [])
        out.insert(TextNorm.pinyin(family).replacingOccurrences(of: " ", with: ""))
        return out
    }

    /// Does the Latin name plausibly belong to the same person as the CJK name?
    /// "David Wang" ↔ "王大明" → true (surname match); "Chen Ming-Hui" ↔ "陳明輝" → true.
    public static func crossScriptMatch(latinGiven: String?, latinFamily: String?, cjkFull: String) -> Double {
        let (fam, given) = splitCJK(cjkFull)
        let romans = romanisations(ofCJKSurname: fam)
        let latinTokens = TextNorm.tokens([latinGiven, latinFamily].compactMap { $0 }.joined(separator: " "))
        guard !latinTokens.isEmpty else { return 0 }
        let familyTok = TextNorm.tokens(latinFamily ?? "").joined()
        var score = 0.0
        if !familyTok.isEmpty && romans.contains(familyTok) { score = 0.75 }
        else if latinTokens.contains(where: { romans.contains($0) }) { score = 0.6 }
        // Given-name romanisation (Taiwanese "Ming-Hui", pinyin "Minghui").
        let givenPinyin = TextNorm.pinyin(given).replacingOccurrences(of: " ", with: "")
        let latinGivenJoined = TextNorm.tokens(latinGiven ?? "").joined()
        if !givenPinyin.isEmpty && !latinGivenJoined.isEmpty {
            if givenPinyin == latinGivenJoined { score += 0.25 }
            else if TextNorm.editDistance(givenPinyin, latinGivenJoined) <= 2 { score += 0.15 }
        }
        return min(score, 1)
    }

    /// True when a string looks like a person's name rather than a company or slogan.
    public static func looksLikePersonName(_ s: String) -> Bool {
        let t = TextNorm.nfkc(s)
        if t.isEmpty || t.count > 40 { return false }
        if t.rangeOfCharacter(from: .decimalDigits) != nil || t.contains("@") || t.contains("www") { return false }
        if CompanyUtil.hasLegalSuffix(t) { return false }
        if TextNorm.containsCJK(t) {
            let n = TextNorm.cjkCount(t)
            return n >= 2 && n <= 4 && isKnownSurname(splitCJK(t).family)
        }
        let words = t.split(separator: " ")
        return words.count >= 1 && words.count <= 4
    }
}

public enum CompanyUtil {
    static let legalSuffixes = ["limited", "ltd", "ltd.", "inc", "inc.", "incorporated", "corp", "corp.", "corporation", "co", "co.",
                                "company", "llc", "l.l.c.", "llp", "lp", "plc", "gmbh", "s.a.", "pte", "pty", "ulc", "group",
                                "holdings", "international", "intl", "enterprises", "trading", "co.,", "co.,ltd", "co.,ltd."]
    static let cjkSuffixes = ["股份有限公司", "有限公司", "有限責任公司", "有限责任公司", "責任有限公司", "公司", "集團", "集团",
                              "企業", "企业", "實業", "实业", "國際", "国际", "工作室", "事務所", "事务所", "商行", "行"]

    public static func hasLegalSuffix(_ s: String) -> Bool {
        let t = TextNorm.loose(s)
        if cjkSuffixes.prefix(6).contains(where: { t.hasSuffix($0) }) { return true }
        let words = t.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let last = words.last else { return false }
        return ["limited", "ltd", "ltd.", "inc", "inc.", "corp", "corp.", "corporation", "llc", "gmbh", "co.", "plc", "ulc", "llp"].contains(last)
    }

    /// Canonical comparison key: lowercase, no punctuation, legal suffixes removed, S/T unified.
    public static func key(_ s: String) -> String {
        var t = TextNorm.toSimplified(TextNorm.loose(s))
        for suf in cjkSuffixes.map(TextNorm.toSimplified) where t.hasSuffix(suf) && t.count > suf.count + 1 {
            t = String(t.dropLast(suf.count))
        }
        var words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "&" }).map(String.init)
        while let last = words.last, words.count > 1, legalSuffixes.contains(last) || legalSuffixes.contains(last + ".") {
            words.removeLast()
        }
        return words.joined()
    }

    /// Similarity between a company name and a web/email domain label ("ABC Foods Ltd." vs "abcfoods").
    public static func domainAffinity(company: String, domainLabel: String) -> Double {
        let k = key(company)
        let d = domainLabel.lowercased().replacingOccurrences(of: "-", with: "")
        guard !k.isEmpty, !d.isEmpty, !TextNorm.containsCJK(k) else { return 0 }
        if k == d || k.hasPrefix(d) || d.hasPrefix(k) { return 1 }
        // Acronym: "Pacific Rim Logistics" → "prl".
        let significant = TextNorm.tokens(company).filter { !legalSuffixes.contains($0) && !legalSuffixes.contains($0 + ".") && $0 != "&" }
        let initials = String(significant.compactMap(\.first))
        if initials.count >= 2 && (d.hasPrefix(initials) || d == initials) { return 0.8 }
        if k.contains(d) || d.contains(k) { return 0.8 }
        let tokens = TextNorm.tokens(company).filter { $0.count >= 3 }
        if tokens.contains(where: { d.contains($0) }) { return 0.6 }
        return 0
    }

    public static func similarity(_ a: String, _ b: String) -> Double {
        let ka = key(a), kb = key(b)
        if ka.isEmpty || kb.isEmpty { return 0 }
        if ka == kb { return 1 }
        return TextNorm.similarity(ka, kb)
    }
}
