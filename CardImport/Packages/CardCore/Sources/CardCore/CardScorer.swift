import Foundation

/// Everything known about one photo after OCR + AI extraction.
public struct CardObservation: Codable, Hashable, Sendable {
    public var photoID: String
    /// Position in the user's selection (0-based).
    public var index: Int
    public var captureDate: Date?
    public var extraction: ExtractedCard
    public var ocr: OCRResult?
    public var visual: VisualSignature?

    public init(photoID: String, index: Int, captureDate: Date? = nil, extraction: ExtractedCard,
                ocr: OCRResult? = nil, visual: VisualSignature? = nil) {
        self.photoID = photoID; self.index = index; self.captureDate = captureDate
        self.extraction = extraction; self.ocr = ocr; self.visual = visual
    }
}

/// Validates one card's extraction and converts it into a single-card ContactDraft
/// whose confidences already include OCR agreement and format validation.
public struct CardScorer: Sendable {
    public var model: ConfidenceModel
    public var defaultRegion: String

    public init(model: ConfidenceModel = ConfidenceModel(), defaultRegion: String = "CA") {
        self.model = model; self.defaultRegion = defaultRegion
    }

    static let titleKeywords = ["manager", "director", "president", "ceo", "cfo", "coo", "cto", "founder", "owner", "partner",
        "sales", "marketing", "engineer", "consultant", "specialist", "officer", "representative", "executive", "vp",
        "vice president", "head", "lead", "supervisor", "coordinator", "assistant", "associate", "analyst", "advisor",
        "agent", "broker", "chairman", "principal", "account", "buyer", "purchasing", "designer", "developer", "chef",
        "經理", "经理", "總監", "总监", "董事", "總經理", "总经理", "主任", "專員", "专员", "副總", "副总", "總裁", "总裁",
        "業務", "业务", "主管", "顧問", "顾问", "工程師", "工程师", "負責人", "负责人", "代表", "協理", "协理", "處長", "处长",
        "課長", "科长", "組長", "组长", "店長", "店长", "執行長", "执行长", "創辦人", "创始人", "秘書", "秘书", "採購", "采购"]

    /// Alternatives that differ only in case, spacing or punctuation are the same reading, not an ambiguity.
    public static func realAlternatives(_ alts: [String], to value: String) -> [String] {
        var seen = Set([TextNorm.alnum(value)])
        var out: [String] = []
        for a in alts where !a.isEmpty {
            let k = TextNorm.alnum(a)
            if seen.insert(k).inserted { out.append(a) }
        }
        return out
    }

    /// Model-supplied country hints are free text in practice ("Hong Kong", "HK", "Canada"): map to ISO alpha-2.
    static func isoRegion(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.count == 2, t.allSatisfy(\.isLetter) { return t.uppercased() == "UK" ? "GB" : t.uppercased() }
        return AddressValidator.inferCountry(ExtractedAddress(country: t, confidence: 1))
    }

    public func regionHint(for card: ExtractedCard) -> String {
        for p in card.phones {
            if let h = Self.isoRegion(p.countryHint) { return h }
            let n = TextNorm.nfkc(p.number)
            if n.hasPrefix("+886") { return "TW" }
            if n.hasPrefix("+86") { return "CN" }
            if n.hasPrefix("+852") { return "HK" }
            if n.hasPrefix("+1") { return defaultRegion == "US" ? "US" : "CA" }
        }
        for a in card.addresses { if let c = AddressValidator.inferCountry(a) { return c } }
        if card.languageHint.contains("zh-Hant") && !card.languageHint.contains("en") { return "TW" }
        if card.languageHint.contains("zh-Hans") && !card.languageHint.contains("en") { return "CN" }
        return defaultRegion
    }

    private func scoreText(_ f: FieldValue?, kind: FieldKind, ocr: OCRResult?, source: String,
                           extra: [(String, Double)] = [], reliability: Double = 1) -> DraftValue? {
        guard let f else { return nil }
        let value = TextNorm.nfkc(f.value)
        guard !value.isEmpty else { return nil }
        let support = OCRCrossCheck.support(value: value, kind: kind, ocr: ocr)
        var deltas = [model.delta(for: support, reliability: reliability)]
        var signals = ["model:\(String(format: "%.2f", f.confidence))", "ocr:\(support.rawValue)"]
        for (name, d) in extra where d != 0 { deltas.append(d); signals.append(name) }
        return DraftValue(value: value, confidence: model.adjust(f.confidence, deltas: deltas),
                          alternatives: Self.realAlternatives(f.alternatives.map(TextNorm.nfkc), to: value), sources: [source], signals: signals)
    }

    public func score(_ obs: CardObservation) -> ContactDraft {
        var card = obs.extraction
        // Chinese-only company / title placed in the Latin slot: keep it in the CJK slot only.
        if let c = card.company, TextNorm.containsCJK(c.value) && !TextNorm.isMostlyLatin(c.value) {
            if card.companyCjk == nil || TextNorm.alnum(card.companyCjk!.value) == TextNorm.alnum(c.value) {
                card.companyCjk = card.companyCjk ?? c; card.company = nil
            }
        }
        if let t = card.jobTitle, TextNorm.containsCJK(t.value) && !TextNorm.isMostlyLatin(t.value) {
            if card.jobTitleCjk == nil || TextNorm.alnum(card.jobTitleCjk!.value) == TextNorm.alnum(t.value) {
                card.jobTitleCjk = card.jobTitleCjk ?? t; card.jobTitle = nil
            }
        }
        // An "alternative" in the other script is a translation printed on the card, not a doubtful reading:
        // move it to the bilingual slot. A combined "品牌部 Brand Studio" alternative is the same text.
        func splitBilingual(_ latin: inout FieldValue?, _ cjk: inout FieldValue?) {
            guard var l = latin else { return }
            if TextNorm.containsCJK(l.value) { return }
            var keep: [String] = []
            for alt in l.alternatives {
                let altIsCJK = TextNorm.containsCJK(alt)
                if altIsCJK && TextNorm.alnum(alt).contains(TextNorm.alnum(l.value)) { continue }          // "品牌部 Brand Studio"
                if altIsCJK && !TextNorm.isMostlyLatin(alt) {
                    if cjk == nil { cjk = FieldValue(alt, confidence: l.confidence, sourceText: l.sourceText) }
                    continue
                }
                keep.append(alt)
            }
            l.alternatives = keep
            latin = l
        }
        splitBilingual(&card.company, &card.companyCjk)
        splitBilingual(&card.jobTitle, &card.jobTitleCjk)
        splitBilingual(&card.department, &card.departmentCjk)
        let ocr = obs.ocr
        let rel = OCRReliability.estimate(card: card, ocr: ocr)
        let src = obs.photoID
        var d = ContactDraft(id: "card-\(obs.photoID)", photoIDs: [obs.photoID])
        d.concerns = card.evidence.concerns + ["ocr_reliability:\(String(format: "%.2f", rel))"]
        d.cardNotes = card.notesOnCard

        // Names
        var nameExtra: [(String, Double)] = []
        if let cjk = card.name.cjkFull?.value, card.name.given != nil || card.name.family != nil {
            let m = NameUtil.crossScriptMatch(latinGiven: card.name.given?.value, latinFamily: card.name.family?.value, cjkFull: cjk)
            if m >= 0.6 { nameExtra.append(("cross_script_match", model.crossScriptNameMatch)) }
            else { nameExtra.append(("cross_script_mismatch", -0.8)) }
        }
        let latinFull = [card.name.given?.value, card.name.family?.value].compactMap { $0 }.joined(separator: " ")
        if !latinFull.isEmpty && !NameUtil.looksLikePersonName(latinFull) { nameExtra.append(("not_name_shaped", -1.2)) }
        d.givenName = scoreText(card.name.given, kind: .personName, ocr: ocr, source: src, extra: nameExtra, reliability: rel)
        d.familyName = scoreText(card.name.family, kind: .personName, ocr: ocr, source: src, extra: nameExtra, reliability: rel)
        var cjkExtra = nameExtra.filter { $0.0 != "not_name_shaped" }
        if let cjk = card.name.cjkFull?.value {
            if !NameUtil.looksLikePersonName(cjk) { cjkExtra.append(("cjk_not_name_shaped", -1.0)) }
            else if NameUtil.isKnownSurname(NameUtil.splitCJK(cjk).family) { cjkExtra.append(("known_surname", 0.4)) }
        }
        d.cjkName = scoreText(card.name.cjkFull, kind: .personName, ocr: ocr, source: src, extra: cjkExtra, reliability: rel)
        d.namePrefix = scoreText(card.name.prefix, kind: .personName, ocr: ocr, source: src, reliability: rel)
        d.nameSuffix = scoreText(card.name.suffix, kind: .personName, ocr: ocr, source: src, reliability: rel)

        // Company / title
        let domains = Set(card.websites.compactMap { DomainUtil.host(fromURL: $0.url) }
            + card.emails.compactMap { EmailValidator.domain(of: EmailValidator.repair($0.address)) }
                .filter { !EmailValidator.freeMailDomains.contains($0) })
        var companyExtra: [(String, Double)] = []
        if let c = card.company?.value {
            let affinity = domains.map { CompanyUtil.domainAffinity(company: c, domainLabel: DomainUtil.label($0)) }.max() ?? 0
            if affinity >= 0.6 { companyExtra.append(("company_matches_domain", 0.8)) }
            if TextNorm.tokens(c).count > 7 && !CompanyUtil.hasLegalSuffix(c) { companyExtra.append(("slogan_shaped", -1.5)) }
            if CompanyUtil.hasLegalSuffix(c) { companyExtra.append(("legal_suffix", 0.4)) }
        }
        d.company = scoreText(card.company, kind: .company, ocr: ocr, source: src, extra: companyExtra, reliability: rel)
        d.companyCJK = scoreText(card.companyCjk, kind: .company, ocr: ocr, source: src,
                                 extra: (card.companyCjk.map { CompanyUtil.hasLegalSuffix($0.value) } ?? false) ? [("legal_suffix", 0.4)] : [], reliability: rel)
        func titleExtra(_ f: FieldValue?) -> [(String, Double)] {
            guard let t = f?.value else { return [] }
            let l = TextNorm.loose(t)
            return Self.titleKeywords.contains(where: { l.contains($0) }) ? [("title_keyword", 0.5)] : []
        }
        d.jobTitle = scoreText(card.jobTitle, kind: .jobTitle, ocr: ocr, source: src, extra: titleExtra(card.jobTitle), reliability: rel)
        d.jobTitleCJK = scoreText(card.jobTitleCjk, kind: .jobTitle, ocr: ocr, source: src, extra: titleExtra(card.jobTitleCjk), reliability: rel)
        if let dp = card.department, TextNorm.containsCJK(dp.value) && !TextNorm.isMostlyLatin(dp.value),
           card.departmentCjk == nil || TextNorm.alnum(card.departmentCjk!.value) == TextNorm.alnum(dp.value) {
            card.departmentCjk = card.departmentCjk ?? dp; card.department = nil
        }
        d.department = scoreText(card.department, kind: .department, ocr: ocr, source: src, reliability: rel)
        d.departmentCJK = scoreText(card.departmentCjk, kind: .department, ocr: ocr, source: src, reliability: rel)

        // Phones
        let region = regionHint(for: card)
        for p in card.phones {
            let hint = Self.isoRegion(p.countryHint) ?? region
            guard let n = PhoneNormalizer.normalize(p.number, regionHint: hint, defaultRegion: defaultRegion,
                                                    extensionHint: p.extension) else { continue }
            let support = OCRCrossCheck.support(value: p.number, kind: .phone, ocr: ocr)
            var deltas = [model.delta(for: support, reliability: rel)]
            var signals = ["model:\(String(format: "%.2f", p.confidence))", "ocr:\(support.rawValue)"]
            if !n.isValid { deltas.append(-2.6); signals.append("validator:invalid_number_plan") }
            var kind = p.kind
            if let labelled = PhoneNormalizer.kindFromLabel(p.sourceText) {
                if labelled != kind { signals.append("kind_from_label:\(labelled.rawValue)") }
                kind = labelled
            }
            if n.planType == .mobile && (kind == .work || kind == .main || kind == .other) { kind = .mobile; signals.append("kind_from_plan:mobile") }
            if n.planType == .mobile && kind == .fax { signals.append("conflict:fax_on_mobile_plan"); deltas.append(-1.0) }
            if d.phones.contains(where: { $0.e164 == n.e164 && $0.extensionNumber == n.extensionNumber }) { continue }
            d.phones.append(DraftPhone(kind: kind, e164: n.e164, printed: TextNorm.nfkc(p.number), extensionNumber: n.extensionNumber,
                                       confidence: model.adjust(p.confidence, deltas: deltas), alternatives: p.alternatives,
                                       sources: [src], signals: signals, isValid: n.isValid))
        }

        // Emails
        for e in card.emails {
            let repaired = EmailValidator.repair(e.address)
            guard repaired.contains("@") else { continue }
            let siblings = Set(card.websites.compactMap { DomainUtil.host(fromURL: $0.url) }
                + card.emails.map { EmailValidator.repair($0.address) }.filter { $0 != repaired }.compactMap { EmailValidator.domain(of: $0) })
            let issues = EmailValidator.validate(repaired, siblingDomains: siblings)
            let support = OCRCrossCheck.support(value: repaired, kind: .email, ocr: ocr)
            var deltas = [model.delta(for: support, reliability: rel)] + issues.map { model.delta(forFactor: $0.factor) }
            var signals = ["model:\(String(format: "%.2f", e.confidence))", "ocr:\(support.rawValue)"] + issues.map { "validator:\($0.code)" }
            if repaired != e.address.lowercased().trimmingCharacters(in: .whitespaces) { signals.append("repaired_from:\(e.address)"); deltas.append(-0.3) }
            if d.emails.contains(where: { $0.value == repaired }) { continue }
            d.emails.append(DraftValue(value: repaired, confidence: model.adjust(e.confidence, deltas: deltas),
                                       alternatives: e.alternatives.map(EmailValidator.repair), sources: [src], signals: signals))
        }

        // Websites
        for w in card.websites {
            let v = TextNorm.nfkc(w.url).lowercased().filter { !$0.isWhitespace }
            guard !v.isEmpty else { continue }
            let support = OCRCrossCheck.support(value: v, kind: .website, ocr: ocr)
            var deltas = [model.delta(for: support, reliability: rel)]
            var signals = ["ocr:\(support.rawValue)"]
            if !DomainUtil.isPlausibleURL(v) { deltas.append(-2.0); signals.append("validator:url_syntax") }
            if let h = DomainUtil.host(fromURL: v), d.emailDomains.contains(where: { DomainUtil.registrable($0) == DomainUtil.registrable(h) }) {
                deltas.append(0.8); signals.append("matches_email_domain")
            }
            if d.websites.contains(where: { DomainUtil.host(fromURL: $0.value) == DomainUtil.host(fromURL: v) }) { continue }
            d.websites.append(DraftValue(value: v, confidence: model.adjust(w.confidence, deltas: deltas), sources: [src], signals: signals))
        }
        // Emails seen before websites were parsed: give the domain-match bonus now.
        for i in d.emails.indices {
            if let dom = EmailValidator.domain(of: d.emails[i].value),
               d.websiteHosts.contains(where: { DomainUtil.registrable($0) == DomainUtil.registrable(dom) }),
               !d.emails[i].signals.contains("validator:email_domain_matches_website") {
                d.emails[i].confidence = model.adjust(d.emails[i].confidence, deltas: [0.6])
                d.emails[i].signals.append("matches_website")
            }
        }

        // Addresses
        for a in card.addresses {
            var a2 = a
            let iso = AddressValidator.inferCountry(a)
            if iso == "CA", let pc = a.postalCode { a2.postalCode = AddressValidator.repairCanadianPostalCode(pc) }
            let issues = AddressValidator.validate(a2)
            let probe = a2.street ?? a2.formatted ?? ""
            let support = probe.isEmpty ? OCRSupport.unavailable : OCRCrossCheck.support(value: probe, kind: .address, ocr: ocr)
            var deltas = [model.delta(for: support, reliability: rel)] + issues.map { model.delta(forFactor: $0.factor) }
            var signals = ["ocr:\(support.rawValue)"] + issues.map { "validator:\($0.code)" }
            if a2.postalCode != a.postalCode { signals.append("postal_code_repaired"); deltas.append(-0.2) }
            let draft = DraftAddress(street: a2.street.map(TextNorm.nfkc), city: a2.city.map(TextNorm.nfkc),
                                     region: AddressValidator.canonicalRegion(a2.region, country: iso),
                                     postalCode: a2.postalCode.map(TextNorm.nfkc), country: a2.country.map(TextNorm.nfkc),
                                     isoCountry: iso, formatted: a2.formatted.map(TextNorm.nfkc),
                                     confidence: model.adjust(a.confidence, deltas: deltas), sources: [src], signals: signals)
            if d.addresses.contains(where: { $0.matchKey == draft.matchKey }) { continue }
            d.addresses.append(draft)
        }

        for s in card.social {
            let support = OCRCrossCheck.support(value: s.handle, kind: .social, ocr: ocr)
            d.social.append(DraftSocial(service: s.service, handle: TextNorm.nfkc(s.handle),
                                        confidence: model.adjust(s.confidence, deltas: [model.delta(for: support, reliability: rel)]), sources: [src]))
        }
        return d
    }
}
