import Foundation

/// Merges the per-photo drafts of one person (front + back, duplicate shots) into one draft.
/// Agreement across sides raises confidence; disagreement lowers it and keeps the loser as an alternative.
public struct DraftMerger: Sendable {
    public var model: ConfidenceModel
    public init(model: ConfidenceModel = ConfidenceModel()) { self.model = model }

    func mergeValue(_ values: [DraftValue?], key: (String) -> String = { TextNorm.alnum($0) }) -> DraftValue? {
        let present = values.compactMap { $0 }
        guard var best = present.max(by: { $0.confidence < $1.confidence }) else { return nil }
        guard present.count > 1 else { return best }
        let agreeing = present.filter { key($0.value) == key(best.value) }
        let disagreeing = present.filter { key($0.value) != key(best.value) }
        best.sources = Array(Set(present.flatMap(\.sources))).sorted()
        if agreeing.count > 1 {
            best.confidence = model.adjust(best.confidence, deltas: [model.crossSideAgree])
            best.signals.append("cross_side_agree")
        }
        if !disagreeing.isEmpty {
            let runner = disagreeing.max(by: { $0.confidence < $1.confidence })!
            // A clearly weaker reading does not hurt much; a close call does.
            let gap = ConfidenceModel.logit(best.confidence) - ConfidenceModel.logit(runner.confidence)
            let penalty = gap > 2.5 ? -0.3 : model.crossSideConflict
            best.confidence = model.adjust(best.confidence, deltas: [penalty])
            best.alternatives = Array(Set(best.alternatives + disagreeing.map(\.value))).sorted()
            best.signals.append("cross_side_conflict")
        }
        return best
    }

    public func merge(id: String, drafts: [ContactDraft]) -> ContactDraft {
        guard drafts.count > 1 else {
            var d = drafts.first ?? ContactDraft(id: id, photoIDs: [])
            d.id = id
            return d
        }
        var m = ContactDraft(id: id, photoIDs: drafts.flatMap(\.photoIDs))
        m.givenName = mergeValue(drafts.map(\.givenName))
        m.familyName = mergeValue(drafts.map(\.familyName))
        m.cjkName = mergeValue(drafts.map(\.cjkName))
        m.namePrefix = mergeValue(drafts.map(\.namePrefix))
        m.nameSuffix = mergeValue(drafts.map(\.nameSuffix))
        m.company = mergeValue(drafts.map(\.company))
        m.companyCJK = mergeValue(drafts.map(\.companyCJK))
        m.jobTitle = mergeValue(drafts.map(\.jobTitle))
        m.jobTitleCJK = mergeValue(drafts.map(\.jobTitleCJK))
        m.department = mergeValue(drafts.map(\.department))
        m.departmentCJK = mergeValue(drafts.map(\.departmentCJK))
        m.concerns = Array(Set(drafts.flatMap(\.concerns))).sorted()
        m.cardNotes = drafts.compactMap(\.cardNotes).first

        // A CJK title/company on one side and Latin on the other are complementary, not conflicting:
        // if the Latin slot got a CJK value (extractor put it in the wrong slot), move it.
        if let t = m.jobTitle, TextNorm.containsCJK(t.value), m.jobTitleCJK == nil { m.jobTitleCJK = t; m.jobTitle = nil }
        if let c = m.company, TextNorm.containsCJK(c.value), m.companyCJK == nil { m.companyCJK = c; m.company = nil }
        if let dp = m.department, TextNorm.containsCJK(dp.value), m.departmentCJK == nil { m.departmentCJK = dp; m.department = nil }

        // Multi-valued: union with agreement bonus.
        var phones: [DraftPhone] = []
        for p in drafts.flatMap(\.phones) {
            if let i = phones.firstIndex(where: { $0.e164 == p.e164 && $0.extensionNumber == p.extensionNumber }) {
                var q = phones[i]
                q.confidence = model.adjust(max(q.confidence, p.confidence), deltas: [model.crossSideAgree])
                q.sources = Array(Set(q.sources + p.sources)).sorted()
                q.signals.append("cross_side_agree")
                if q.kind != p.kind {
                    // Prefer label-derived kinds; fax beats generic.
                    if p.signals.contains(where: { $0.hasPrefix("kind_from_label") }) { q.kind = p.kind }
                }
                phones[i] = q
            } else { phones.append(p) }
        }
        m.phones = phones
        var emails: [DraftValue] = []
        for e in drafts.flatMap(\.emails) {
            if let i = emails.firstIndex(where: { $0.value == e.value }) {
                emails[i].confidence = model.adjust(max(emails[i].confidence, e.confidence), deltas: [model.crossSideAgree])
                emails[i].sources = Array(Set(emails[i].sources + e.sources)).sorted()
                emails[i].signals.append("cross_side_agree")
            } else if let i = emails.firstIndex(where: { TextNorm.editDistance($0.value, e.value) <= 2 }) {
                // Same address read differently on two sides: keep the stronger, flag both.
                let keep = emails[i].confidence >= e.confidence ? emails[i] : e
                let lose = emails[i].confidence >= e.confidence ? e : emails[i]
                var k = keep
                k.alternatives = Array(Set(k.alternatives + [lose.value])).sorted()
                k.confidence = model.adjust(k.confidence, deltas: [model.crossSideConflict])
                k.signals.append("cross_side_conflict")
                emails[i] = k
            } else { emails.append(e) }
        }
        m.emails = emails
        var sites: [DraftValue] = []
        for w in drafts.flatMap(\.websites) {
            if let i = sites.firstIndex(where: { DomainUtil.host(fromURL: $0.value) == DomainUtil.host(fromURL: w.value) }) {
                sites[i].confidence = model.adjust(max(sites[i].confidence, w.confidence), deltas: [model.crossSideAgree])
                sites[i].sources = Array(Set(sites[i].sources + w.sources)).sorted()
            } else { sites.append(w) }
        }
        m.websites = sites
        var addrs: [DraftAddress] = []
        for a in drafts.flatMap(\.addresses) {
            if let i = addrs.firstIndex(where: { $0.matchKey == a.matchKey && !a.matchKey.isEmpty }) {
                // Same address in two languages: keep the more complete / confident version.
                var keep = (addrs[i].confidence >= a.confidence) ? addrs[i] : a
                keep.confidence = model.adjust(max(addrs[i].confidence, a.confidence), deltas: [1.0])
                keep.sources = Array(Set(addrs[i].sources + a.sources)).sorted()
                addrs[i] = keep
            } else { addrs.append(a) }
        }
        m.addresses = addrs
        var social: [DraftSocial] = []
        for s in drafts.flatMap(\.social) where !social.contains(where: { $0.service == s.service && TextNorm.alnum($0.handle) == TextNorm.alnum(s.handle) }) {
            social.append(s)
        }
        m.social = social
        return m
    }
}
