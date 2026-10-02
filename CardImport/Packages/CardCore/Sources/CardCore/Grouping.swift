import Foundation

/// Explains why two photos were (or were not) considered the same card / person.
public struct PairEvidence: Codable, Hashable, Sendable {
    public var a: String
    public var b: String
    public var score: Double
    public var signals: [String]
    /// Hard veto: the two photos name different people.
    public var conflict: Bool
    /// Score from content (identity + company-level evidence) only. Weak signals such as capture time,
    /// colour or front/back labels can rank candidates but can never merge two photos on their own.
    public var contentScore: Double = 0
}

public struct GroupingResult: Codable, Hashable, Sendable {
    /// Photo-ID groups; each group is one person.
    public var groups: [[String]]
    /// Photos whose assignment is uncertain: photoID → candidate group indices (best first).
    public var ambiguous: [String: [Int]]
    /// Photos with no usable contact data (decorative backs, non-cards).
    public var empty: [String]
    public var pairs: [PairEvidence]
}

public struct GroupingConfig: Codable, Sendable {
    public var mergeThreshold = 3.0
    /// Nameless sides need a clear winner: best − runner-up must exceed this.
    public var ambiguityMargin = 1.5
    /// Minimum content evidence (identity or company-level) for any merge.
    public var minContentScore = 1.5
    public init() {}
}

/// Decides which photos belong to the same person (front/back pairs, duplicate shots).
/// Deterministic, explainable scoring; the LLM resolver is only consulted for `ambiguous` items.
public struct FrontBackMatcher: Sendable {
    public var config: GroupingConfig
    public init(config: GroupingConfig = GroupingConfig()) { self.config = config }

    struct Side {
        let obs: CardObservation
        let draft: ContactDraft
        var id: String { obs.photoID }
        var hasName: Bool { draft.hasPersonName }
    }

    public func pairEvidence(_ x: (CardObservation, ContactDraft), _ y: (CardObservation, ContactDraft)) -> PairEvidence {
        let a = Side(obs: x.0, draft: x.1), b = Side(obs: y.0, draft: y.1)
        var s = 0.0
        var content = 0.0
        var sig: [String] = []
        var conflict = false

        // Identity keys.
        let emailsA = Set(a.draft.emails.map(\.value)), emailsB = Set(b.draft.emails.map(\.value))
        if !emailsA.isDisjoint(with: emailsB) { s += 4; content += 4; sig.append("same_email") }
        let personalPhones: (ContactDraft) -> Set<String> = { Set($0.phones.filter { $0.kind == .mobile }.map(\.e164)) }
        let sharedPhones: (ContactDraft) -> Set<String> = { Set($0.phones.filter { $0.kind != .mobile }.map { $0.e164 + ($0.extensionNumber ?? "") }) }
        if !personalPhones(a.draft).isDisjoint(with: personalPhones(b.draft)) { s += 3.5; content += 3.5; sig.append("same_mobile") }

        // Contradicting personal contacts: both sides print emails / mobiles and none match → different people.
        if !emailsA.isEmpty && !emailsB.isEmpty && emailsA.isDisjoint(with: emailsB) {
            let dA = Set(emailsA.compactMap(EmailValidator.domain(of:)).map(DomainUtil.registrable))
            let dB = Set(emailsB.compactMap(EmailValidator.domain(of:)).map(DomainUtil.registrable))
            if dA.isDisjoint(with: dB) { s -= 4; sig.append("different_email_domains") }
        }
        if !personalPhones(a.draft).isEmpty && !personalPhones(b.draft).isEmpty && personalPhones(a.draft).isDisjoint(with: personalPhones(b.draft)) {
            s -= 3; sig.append("different_mobiles")
        }

        // Company-level evidence is shared by every colleague, so it is capped: it can say "same company",
        // never "same person".
        var companyLevel = 0.0
        if !sharedPhones(a.draft).isDisjoint(with: sharedPhones(b.draft)) { companyLevel += 1.5; sig.append("same_office_phone") }
        let domA = a.draft.emailDomains.union(a.draft.websiteHosts).map(DomainUtil.registrable)
        let domB = b.draft.emailDomains.union(b.draft.websiteHosts).map(DomainUtil.registrable)
        if !Set(domA).isDisjoint(with: Set(domB)) { companyLevel += 1.5; sig.append("same_domain") }
        var companyMatched = false
        for (ca, cb) in [(a.draft.company, b.draft.company), (a.draft.companyCJK, b.draft.companyCJK)] {
            if let ca, let cb, CompanyUtil.similarity(ca.value, cb.value) >= 0.85 { companyMatched = true }
        }
        if !companyMatched {
            for (side, other) in [(a, domB), (b, domA)] {
                if let c = side.draft.company?.value,
                   other.contains(where: { CompanyUtil.domainAffinity(company: c, domainLabel: DomainUtil.label($0)) >= 0.8 }) {
                    companyMatched = true
                }
            }
        }
        if companyMatched { companyLevel += 2; sig.append("same_company") }
        let addrA = Set(a.draft.addresses.map(\.matchKey).filter { !$0.isEmpty }), addrB = Set(b.draft.addresses.map(\.matchKey).filter { !$0.isEmpty })
        if !addrA.isDisjoint(with: addrB) { companyLevel += 1; sig.append("same_address") }
        s += min(companyLevel, 2.5)
        content += min(companyLevel, 2.5)

        // Names.
        if a.hasName && b.hasName {
            let r = nameRelation(a.draft, b.draft)
            switch r {
            case .same: s += 3; content += 3; sig.append("same_name")
            case .crossScript: s += 2.5; content += 2.5; sig.append("cross_script_name")
            case .crossScriptSurnameOnly: s += 0.5; content += 0.5; sig.append("cross_script_surname_only")
            case .different: conflict = true; sig.append("different_names")
            case .incomparable: sig.append("names_incomparable")
            }
        } else if a.hasName != b.hasName {
            s += 0.8; sig.append("complementary_sides")
        }
        let sideA = a.obs.extraction.cardSide, sideB = b.obs.extraction.cardSide
        if (sideA == .front && sideB == .back) || (sideA == .back && sideB == .front) { s += 0.5; sig.append("front_back_labels") }

        // Capture time adjacency (EXIF, read on-device without Photos permission).
        if let ta = a.obs.captureDate, let tb = b.obs.captureDate {
            let dt = abs(ta.timeIntervalSince(tb))
            if dt <= 20 { s += 2.5; sig.append("shot_within_20s") }
            else if dt <= 60 { s += 1.5; sig.append("shot_within_60s") }
            else if dt <= 180 { s += 0.5; sig.append("shot_within_3min") }
            else if dt > 600 { s -= 1.0; sig.append("shot_far_apart") }
        }
        // Visual similarity of the card (paper colour / brand colour).
        if let va = a.obs.visual, let vb = b.obs.visual {
            let sim = cosine(va.colorHistogram, vb.colorHistogram)
            if sim >= 0.92 { s += 0.8; sig.append("similar_colours") }
            else if sim < 0.5 { s -= 0.5; sig.append("different_colours") }
            if let ra = va.aspectRatio, let rb = vb.aspectRatio, abs(ra - rb) > 0.15 { s -= 0.5; sig.append("different_aspect") }
        }
        if abs(a.obs.index - b.obs.index) == 1 { s += 0.3; sig.append("adjacent_in_selection") }
        if conflict { s = -10; content = 0 }
        return PairEvidence(a: a.id, b: b.id, score: s, signals: sig, conflict: conflict, contentScore: content)
    }

    enum NameRelation { case same, crossScript, crossScriptSurnameOnly, different, incomparable }

    func nameRelation(_ x: ContactDraft, _ y: ContactDraft) -> NameRelation {
        let latinX = [x.givenName?.value, x.familyName?.value].compactMap { $0 }.joined(separator: " ")
        let latinY = [y.givenName?.value, y.familyName?.value].compactMap { $0 }.joined(separator: " ")
        var anySame = false, anyDifferent = false
        if !latinX.isEmpty && !latinY.isEmpty {
            // One letter can be a different person (Chang/Zhang, Lee/Lei): only identical names, or names that differ
            // purely by OCR-confusable characters, count as the same.
            let tx = Set(TextNorm.tokens(latinX)), ty = Set(TextNorm.tokens(latinY))
            if tx == ty || TextNorm.confusableFold(TextNorm.alnum(latinX)) == TextNorm.confusableFold(TextNorm.alnum(latinY)) {
                anySame = true
            } else { anyDifferent = true }
        }
        if let cx = x.cjkName?.value, let cy = y.cjkName?.value {
            if TextNorm.toSimplified(TextNorm.alnum(cx)) == TextNorm.toSimplified(TextNorm.alnum(cy)) { anySame = true } else { anyDifferent = true }
        }
        if anySame && !anyDifferent { return .same }
        if anyDifferent { return .different }
        // Only cross-script comparison possible.
        let pairs: [(ContactDraft, ContactDraft)] = [(x, y), (y, x)]
        for (l, c) in pairs {
            if let cjk = c.cjkName?.value, l.givenName != nil || l.familyName != nil {
                let m = NameUtil.crossScriptMatch(latinGiven: l.givenName?.value, latinFamily: l.familyName?.value, cjkFull: cjk)
                // Surname alone is weak evidence (Wang, Chen, Lee… are extremely common); the given name must
                // also match (pinyin / Wade–Giles) for a strong cross-script link.
                if m >= 0.9 { return .crossScript }
                if m >= 0.6 { return .crossScriptSurnameOnly }
                return .different
            }
        }
        return .incomparable
    }

    func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return (na == 0 || nb == 0) ? 0 : dot / (na.squareRoot() * nb.squareRoot())
    }

    public func group(_ items: [(CardObservation, ContactDraft)]) -> GroupingResult {
        let empty = items.filter { $0.1.isEmpty || !$0.0.extraction.isBusinessCard }.map(\.0.photoID)
        let usable = items.filter { !empty.contains($0.0.photoID) }
        var pairs: [PairEvidence] = []
        for i in usable.indices { for j in usable.indices where j > i { pairs.append(pairEvidence(usable[i], usable[j])) } }

        // Union-find over named sides first, then attach nameless sides with an ambiguity check.
        var groupOf: [String: Int] = [:]
        var groups: [[String]] = []
        let named = usable.filter { $0.1.hasPersonName }.map(\.0.photoID)
        let nameless = usable.filter { !$0.1.hasPersonName }.map(\.0.photoID)
        func evidence(_ x: String, _ y: String) -> PairEvidence? { pairs.first { ($0.a == x && $0.b == y) || ($0.a == y && $0.b == x) } }
        func groupConflicts(_ g: Int, _ id: String) -> Bool { groups[g].contains { evidence($0, id)?.conflict ?? false } }

        for e in pairs.sorted(by: { $0.score > $1.score }) where e.score >= config.mergeThreshold && e.contentScore >= config.minContentScore {
            guard named.contains(e.a) && named.contains(e.b) else { continue }
            switch (groupOf[e.a], groupOf[e.b]) {
            case (nil, nil):
                groups.append([e.a, e.b]); groupOf[e.a] = groups.count - 1; groupOf[e.b] = groups.count - 1
            case (let g?, nil):
                if !groupConflicts(g, e.b) { groups[g].append(e.b); groupOf[e.b] = g }
            case (nil, let g?):
                if !groupConflicts(g, e.a) { groups[g].append(e.a); groupOf[e.a] = g }
            case (let g1?, let g2?) where g1 != g2:
                if !groups[g2].contains(where: { groupConflicts(g1, $0) }) {
                    for id in groups[g2] { groupOf[id] = g1 }
                    groups[g1] += groups[g2]; groups[g2] = []
                }
            default: break
            }
        }
        for id in named where groupOf[id] == nil { groups.append([id]); groupOf[id] = groups.count - 1 }

        var ambiguous: [String: [Int]] = [:]
        // Nameless sides: attach to the best named group if clearly best; otherwise stand alone or be ambiguous.
        var namelessAlone: [String] = []
        let timeOf: [String: Date] = Dictionary(uniqueKeysWithValues: usable.compactMap { o in o.0.captureDate.map { (o.0.photoID, $0) } })
        for id in nameless {
            // People photograph a card's front and back back-to-back: the photo taken right before/after a
            // nameless side (within 30 s) is strong evidence when it is also a content-linked candidate.
            var nearestGroup: Int? = nil
            if let t = timeOf[id] {
                let near = timeOf.filter { $0.key != id }.min { abs($0.value.timeIntervalSince(t)) < abs($1.value.timeIntervalSince(t)) }
                if let near, abs(near.value.timeIntervalSince(t)) <= 30 { nearestGroup = groupOf[near.key] }
            }
            var scores: [(Int, Double)] = []
            for (gi, g) in groups.enumerated() where !g.isEmpty {
                var best = g.compactMap { m -> Double? in
                    guard let e = evidence(m, id), e.contentScore >= config.minContentScore else { return nil }
                    return e.score
                }.max() ?? -10
                if gi == nearestGroup && best > -10 { best += 1.5 }
                scores.append((gi, best))
            }
            scores.sort { $0.1 > $1.1 }
            guard let top = scores.first, top.1 >= config.mergeThreshold else { namelessAlone.append(id); continue }
            let runner = scores.dropFirst().first?.1 ?? -10
            if top.1 - runner >= config.ambiguityMargin {
                groups[top.0].append(id); groupOf[id] = top.0
            } else {
                ambiguous[id] = scores.prefix(3).filter { $0.1 >= config.mergeThreshold - config.ambiguityMargin }.map(\.0)
            }
        }
        // Nameless sides that did not attach anywhere: merge them with each other if they match (company-only cards).
        for id in namelessAlone {
            if let g = groups.indices.first(where: { gi in
                !groups[gi].isEmpty && groups[gi].allSatisfy { nameless.contains($0) } && groups[gi].contains {
                    guard let e = evidence($0, id) else { return false }
                    return e.score >= config.mergeThreshold && e.contentScore >= config.minContentScore
                }
            }) {
                groups[g].append(id); groupOf[id] = g
            } else {
                groups.append([id]); groupOf[id] = groups.count - 1
            }
        }
        // Compact (remove emptied groups) and remap ambiguous indices.
        var remap: [Int: Int] = [:]
        var compact: [[String]] = []
        for (i, g) in groups.enumerated() where !g.isEmpty {
            remap[i] = compact.count
            compact.append(g.sorted { a, b in
                let ia = items.first { $0.0.photoID == a }?.0.index ?? 0
                let ib = items.first { $0.0.photoID == b }?.0.index ?? 0
                return ia < ib
            })
        }
        let amb = ambiguous.mapValues { $0.compactMap { remap[$0] } }
        return GroupingResult(groups: compact, ambiguous: amb, empty: empty, pairs: pairs)
    }
}
