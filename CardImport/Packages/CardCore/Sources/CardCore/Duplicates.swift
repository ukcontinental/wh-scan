import Foundation

/// Platform-neutral snapshot of an existing address-book contact.
public struct ExistingContact: Codable, Hashable, Sendable {
    public var identifier: String
    public var givenName: String
    public var familyName: String
    public var nickname: String
    public var organization: String
    public var jobTitle: String
    public var phones: [String]
    public var emails: [String]
    public var urls: [String]

    public init(identifier: String, givenName: String = "", familyName: String = "", nickname: String = "",
                organization: String = "", jobTitle: String = "", phones: [String] = [], emails: [String] = [], urls: [String] = []) {
        self.identifier = identifier; self.givenName = givenName; self.familyName = familyName; self.nickname = nickname
        self.organization = organization; self.jobTitle = jobTitle; self.phones = phones; self.emails = emails; self.urls = urls
    }

    public var displayName: String {
        let n = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return n.isEmpty ? (nickname.isEmpty ? organization : nickname) : n
    }
}

/// Looks up possible matches in the user's address book (CNContactStore on iOS, in-memory in tests).
public protocol ContactIndex: Sendable {
    func candidates(for draft: ContactDraft) async throws -> [ExistingContact]
}

public struct InMemoryContactIndex: ContactIndex {
    public var contacts: [ExistingContact]
    public init(_ contacts: [ExistingContact]) { self.contacts = contacts }
    public func candidates(for draft: ContactDraft) async throws -> [ExistingContact] { contacts }
}

/// Thrown by a ContactIndex / ContactWriter when the address book cannot be accessed. The batch pauses
/// (people stay pending) instead of marking them failed.
public enum ContactStoreError: Error, Sendable {
    case notAuthorized
}

public enum DuplicateVerdict: String, Codable, Sendable {
    case new                 // no plausible match → create
    case alreadyExists       // same person, nothing new → skip
    case update              // same person, only additive changes → auto-update
    case updateWithConflicts // same person, additive changes applied; conflicting values go to review
    case uncertain           // maybe the same person → review
}

public struct FieldConflict: Codable, Hashable, Sendable {
    public var field: String
    public var existing: String
    public var incoming: String
}

public struct DuplicateAssessment: Codable, Hashable, Sendable {
    public var verdict: DuplicateVerdict
    public var match: ExistingContact?
    public var score: Double
    public var signals: [String]
    /// Draft fields missing from the existing contact (safe to add).
    public var additions: [String]
    public var conflicts: [FieldConflict]
}

public struct DuplicateDetector: Sendable {
    public var defaultRegion: String
    public var sameThreshold = 0.75
    public var uncertainThreshold = 0.45

    public init(defaultRegion: String = "CA") { self.defaultRegion = defaultRegion }

    func normPhones(_ list: [String]) -> Set<String> {
        Set(list.compactMap { PhoneNormalizer.normalize($0, regionHint: defaultRegion, defaultRegion: defaultRegion)?.e164 })
    }

    public func score(_ d: ContactDraft, _ c: ExistingContact) -> (Double, [String]) {
        var s = 0.0
        var sig: [String] = []
        let cEmails = Set(c.emails.map { EmailValidator.repair($0) })
        if d.emails.contains(where: { cEmails.contains($0.value) }) { s += 0.6; sig.append("email") }
        let cPhones = normPhones(c.phones)
        if d.phones.contains(where: { $0.kind == .mobile && cPhones.contains($0.e164) }) { s += 0.5; sig.append("mobile") }
        else if d.phones.contains(where: { $0.kind != .fax && cPhones.contains($0.e164) }) { s += 0.25; sig.append("office_phone") }

        let latin = [d.givenName?.value, d.familyName?.value].compactMap { $0 }.joined(separator: " ")
        let cLatin = [c.givenName, c.familyName].filter { !$0.isEmpty && !TextNorm.containsCJK($0) }.joined(separator: " ")
        let cCJK = [c.familyName + c.givenName, c.nickname].first { TextNorm.containsCJK($0) } ?? ""
        var nameSame = false, nameDifferent = false
        if !latin.isEmpty && !cLatin.isEmpty {
            if Set(TextNorm.tokens(latin)) == Set(TextNorm.tokens(cLatin)) || TextNorm.similarity(latin, cLatin) >= 0.88 { nameSame = true }
            else if TextNorm.tokens(latin).last != TextNorm.tokens(cLatin).last { nameDifferent = true }
        }
        if let cjk = d.cjkName?.value, !cCJK.isEmpty {
            if TextNorm.toSimplified(cjk) == TextNorm.toSimplified(cCJK.filter { !$0.isWhitespace }) { nameSame = true } else { nameDifferent = true }
        }
        if !nameSame && !nameDifferent {
            if let cjk = d.cjkName?.value, !cLatin.isEmpty,
               NameUtil.crossScriptMatch(latinGiven: c.givenName, latinFamily: c.familyName, cjkFull: cjk) >= 0.75 {
                s += 0.2; sig.append("cross_script_name")
            }
        }
        if nameSame { s += 0.35; sig.append("name") }
        if nameDifferent { s -= 0.6; sig.append("different_name") }
        let comp = d.company?.value ?? d.companyCJK?.value
        if let comp, !c.organization.isEmpty, CompanyUtil.similarity(comp, c.organization) >= 0.85 { s += 0.15; sig.append("company") }
        let hosts = Set(c.urls.compactMap(DomainUtil.host(fromURL:)))
        if d.websites.contains(where: { DomainUtil.host(fromURL: $0.value).map(hosts.contains) ?? false }) { s += 0.15; sig.append("website") }
        return (min(max(s, 0), 1), sig)
    }

    public func assess(_ d: ContactDraft, against candidates: [ExistingContact]) -> DuplicateAssessment {
        // A contact that already holds everything this card says (and nothing contradicting it) is the same
        // contact — e.g. the one we wrote just before the app was killed, or a card imported twice.
        for c in candidates {
            let (s, sig) = score(d, c)
            guard !sig.contains("different_name") else { continue }
            let (adds, conflicts) = diff(d, c)
            if adds.isEmpty && conflicts.isEmpty && identifyingMatches(d, c) >= 2 {
                return DuplicateAssessment(verdict: .alreadyExists, match: c, score: max(s, sameThreshold), signals: sig + ["identical"],
                                           additions: [], conflicts: [])
            }
        }
        let scored = candidates.map { ($0, score(d, $0)) }.sorted { $0.1.0 > $1.1.0 }
        guard let (best, (s, sig)) = scored.first, s >= uncertainThreshold else {
            return DuplicateAssessment(verdict: .new, match: nil, score: scored.first?.1.0 ?? 0, signals: scored.first?.1.1 ?? [], additions: [], conflicts: [])
        }
        if s < sameThreshold {
            return DuplicateAssessment(verdict: .uncertain, match: best, score: s, signals: sig, additions: [], conflicts: [])
        }
        let (adds, conflicts) = diff(d, best)
        let verdict: DuplicateVerdict = adds.isEmpty && conflicts.isEmpty ? .alreadyExists : (conflicts.isEmpty ? .update : .updateWithConflicts)
        return DuplicateAssessment(verdict: verdict, match: best, score: s, signals: sig, additions: adds, conflicts: conflicts)
    }

    /// How many identifying values of the draft the contact already holds (name, organisation, phones, emails, sites).
    func identifyingMatches(_ d: ContactDraft, _ c: ExistingContact) -> Int {
        var n = 0
        let latin = [d.givenName?.value, d.familyName?.value].compactMap { $0 }.joined(separator: " ")
        let cLatin = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !latin.isEmpty && Set(TextNorm.tokens(latin)) == Set(TextNorm.tokens(cLatin)) { n += 1 }
        if let cjk = d.cjkName?.value, [c.familyName + c.givenName, c.nickname].contains(where: { TextNorm.toSimplified($0) == TextNorm.toSimplified(cjk) }) { n += 1 }
        if let comp = d.company?.value ?? d.companyCJK?.value, !c.organization.isEmpty, c.organization.contains(comp) || CompanyUtil.similarity(comp, c.organization) >= 0.85 { n += 1 }
        let cPhones = normPhones(c.phones)
        n += d.phones.filter { cPhones.contains($0.e164) }.count
        let cEmails = Set(c.emails.map { EmailValidator.repair($0) })
        n += d.emails.filter { cEmails.contains($0.value) }.count
        let hosts = Set(c.urls.compactMap(DomainUtil.host(fromURL:)))
        n += d.websites.filter { DomainUtil.host(fromURL: $0.value).map(hosts.contains) ?? false }.count
        return n
    }

    /// Additive differences (safe) and conflicting single-valued fields (need a decision).
    public func diff(_ d: ContactDraft, _ c: ExistingContact) -> ([String], [FieldConflict]) {
        var adds: [String] = []
        var conflicts: [FieldConflict] = []
        let cPhones = normPhones(c.phones)
        for p in d.phones where !cPhones.contains(p.e164) { adds.append("phone:\(p.e164)") }
        let cEmails = Set(c.emails.map { EmailValidator.repair($0) })
        for e in d.emails where !cEmails.contains(e.value) { adds.append("email:\(e.value)") }
        let cHosts = Set(c.urls.compactMap(DomainUtil.host(fromURL:)))
        for w in d.websites where !(DomainUtil.host(fromURL: w.value).map(cHosts.contains) ?? false) { adds.append("website:\(w.value)") }
        func single(_ name: String, _ new: String?, _ old: String) {
            guard let new, !new.isEmpty else { return }
            if old.isEmpty { adds.append("\(name):\(new)") }
            else if TextNorm.alnum(TextNorm.toSimplified(new)) != TextNorm.alnum(TextNorm.toSimplified(old)) && CompanyUtil.similarity(new, old) < 0.85 {
                conflicts.append(FieldConflict(field: name, existing: old, incoming: new))
            }
        }
        single("organization", d.company?.value ?? d.companyCJK?.value, c.organization)
        single("job_title", d.jobTitle?.value ?? d.jobTitleCJK?.value, c.jobTitle)
        if let cjk = d.cjkName?.value, !TextNorm.containsCJK(c.familyName + c.givenName + c.nickname) { adds.append("cjk_name:\(cjk)") }
        return (adds, conflicts)
    }
}
