import Foundation

/// One value in a contact draft after validation, with provenance.
public struct DraftValue: Codable, Hashable, Sendable {
    public var value: String
    public var confidence: Double
    public var alternatives: [String]
    /// Photo IDs this value was read from.
    public var sources: [String]
    /// Audit trail of signals that moved the confidence (e.g. "ocr:strong", "validator:email_syntax").
    public var signals: [String]

    public init(value: String, confidence: Double, alternatives: [String] = [], sources: [String] = [], signals: [String] = []) {
        self.value = value; self.confidence = confidence; self.alternatives = alternatives
        self.sources = sources; self.signals = signals
    }
}

public struct DraftPhone: Codable, Hashable, Sendable {
    public var kind: PhoneKind
    public var e164: String
    /// As printed (used for display/review only).
    public var printed: String
    public var extensionNumber: String?
    public var confidence: Double
    public var alternatives: [String]
    public var sources: [String]
    public var signals: [String]
    public var isValid: Bool

    public init(kind: PhoneKind, e164: String, printed: String, extensionNumber: String? = nil, confidence: Double,
                alternatives: [String] = [], sources: [String] = [], signals: [String] = [], isValid: Bool = true) {
        self.kind = kind; self.e164 = e164; self.printed = printed; self.extensionNumber = extensionNumber
        self.confidence = confidence; self.alternatives = alternatives; self.sources = sources
        self.signals = signals; self.isValid = isValid
    }
}

public struct DraftAddress: Codable, Hashable, Sendable {
    public var street: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?
    public var country: String?
    public var isoCountry: String?
    public var formatted: String?
    public var confidence: Double
    public var sources: [String]
    public var signals: [String]

    public init(street: String? = nil, city: String? = nil, region: String? = nil, postalCode: String? = nil,
                country: String? = nil, isoCountry: String? = nil, formatted: String? = nil, confidence: Double,
                sources: [String] = [], signals: [String] = []) {
        self.street = street; self.city = city; self.region = region; self.postalCode = postalCode
        self.country = country; self.isoCountry = isoCountry; self.formatted = formatted
        self.confidence = confidence; self.sources = sources; self.signals = signals
    }

    /// Key for de-duplicating the same address read from two sides.
    public var matchKey: String {
        let pc = TextNorm.alnum(postalCode ?? "")
        let st = TextNorm.alnum(street ?? formatted ?? "")
        return pc.isEmpty ? String(st.prefix(18)) : pc + String(TextNorm.digits(street ?? "").prefix(6))
    }
}

public struct DraftSocial: Codable, Hashable, Sendable {
    public var service: String
    public var handle: String
    public var confidence: Double
    public var sources: [String]

    public init(service: String, handle: String, confidence: Double, sources: [String] = []) {
        self.service = service; self.handle = handle; self.confidence = confidence; self.sources = sources
    }
}

/// The merged, validated representation of one person, ready for policy + Contacts.
public struct ContactDraft: Codable, Hashable, Sendable {
    public var id: String
    public var photoIDs: [String]
    public var givenName: DraftValue?
    public var familyName: DraftValue?
    public var cjkName: DraftValue?
    public var namePrefix: DraftValue?
    public var nameSuffix: DraftValue?
    public var company: DraftValue?
    public var companyCJK: DraftValue?
    public var jobTitle: DraftValue?
    public var jobTitleCJK: DraftValue?
    public var department: DraftValue?
    public var departmentCJK: DraftValue?
    public var phones: [DraftPhone]
    public var emails: [DraftValue]
    public var websites: [DraftValue]
    public var addresses: [DraftAddress]
    public var social: [DraftSocial]
    public var cardNotes: String?
    /// Card-level concerns raised by the extractor (e.g. "two_people_on_card").
    public var concerns: [String]

    public init(id: String, photoIDs: [String]) {
        self.id = id; self.photoIDs = photoIDs
        phones = []; emails = []; websites = []; addresses = []; social = []; concerns = []
    }

    public var hasPersonName: Bool { givenName != nil || familyName != nil || cjkName != nil }
    public var hasAnyContactMethod: Bool { !phones.isEmpty || !emails.isEmpty }
    /// No contact data at all (decorative back side).
    public var isEmpty: Bool {
        !hasPersonName && company == nil && companyCJK == nil && phones.isEmpty && emails.isEmpty
            && websites.isEmpty && addresses.isEmpty && social.isEmpty
    }

    /// Nothing to write (used for patches, where a lone job title is meaningful).
    public var hasNoFields: Bool {
        isEmpty && jobTitle == nil && jobTitleCJK == nil && department == nil && departmentCJK == nil && namePrefix == nil && nameSuffix == nil
    }

    /// Human readable label for the summary and review screens.
    public var displayName: String {
        let latin = [givenName?.value, familyName?.value].compactMap { $0 }.joined(separator: " ")
        let parts = [latin.isEmpty ? nil : latin, cjkName?.value].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " / ") }
        return company?.value ?? companyCJK?.value ?? emails.first?.value ?? phones.first?.printed ?? "(unknown)"
    }

    public var emailDomains: Set<String> {
        Set(emails.compactMap { EmailValidator.domain(of: $0.value) }.filter { !EmailValidator.freeMailDomains.contains($0) })
    }

    public var websiteHosts: Set<String> { Set(websites.compactMap { DomainUtil.host(fromURL: $0.value) }) }
}

/// Identifies one field of a draft for review / held fields.
public enum FieldRef: Codable, Hashable, Sendable, CustomStringConvertible {
    case givenName, familyName, cjkName, company, companyCJK, jobTitle, jobTitleCJK, department, departmentCJK
    case phone(String)      // e164
    case email(String)      // address
    case website(String)
    case address(String)    // matchKey
    case social(String)

    public var description: String {
        switch self {
        case .givenName: return "given_name"
        case .familyName: return "family_name"
        case .cjkName: return "cjk_name"
        case .company: return "company"
        case .companyCJK: return "company_cjk"
        case .jobTitle: return "job_title"
        case .jobTitleCJK: return "job_title_cjk"
        case .department: return "department"
        case .departmentCJK: return "department_cjk"
        case .phone(let v): return "phone:\(v)"
        case .email(let v): return "email:\(v)"
        case .website(let v): return "website:\(v)"
        case .address(let v): return "address:\(v)"
        case .social(let v): return "social:\(v)"
        }
    }

    public var isNameField: Bool {
        switch self { case .givenName, .familyName, .cjkName: return true; default: return false }
    }

    public var kind: FieldKind {
        switch self {
        case .givenName, .familyName, .cjkName: return .personName
        case .company, .companyCJK: return .company
        case .jobTitle, .jobTitleCJK: return .jobTitle
        case .department, .departmentCJK: return .department
        case .phone: return .phone
        case .email: return .email
        case .website: return .website
        case .address: return .address
        case .social: return .social
        }
    }
}

extension ContactDraft {
    /// Every (field, value, confidence) triple, for policy evaluation.
    public func allFields() -> [(FieldRef, String, Double, [String])] {
        var out: [(FieldRef, String, Double, [String])] = []
        func add(_ r: FieldRef, _ v: DraftValue?) { if let v { out.append((r, v.value, v.confidence, v.alternatives)) } }
        add(.givenName, givenName); add(.familyName, familyName); add(.cjkName, cjkName)
        add(.company, company); add(.companyCJK, companyCJK); add(.jobTitle, jobTitle); add(.jobTitleCJK, jobTitleCJK)
        add(.department, department); add(.departmentCJK, departmentCJK)
        for p in phones {
            var shown = p.printed
            if let ext = p.extensionNumber, !TextNorm.digits(shown).hasSuffix(ext) { shown += " ext. \(ext)" }
            out.append((.phone(p.e164), shown, p.confidence, p.alternatives))
        }
        for e in emails { out.append((.email(e.value), e.value, e.confidence, e.alternatives)) }
        for w in websites { out.append((.website(w.value), w.value, w.confidence, w.alternatives)) }
        for a in addresses { out.append((.address(a.matchKey), a.formatted ?? [a.street, a.city].compactMap { $0 }.joined(separator: ", "), a.confidence, [])) }
        for s in social { out.append((.social(s.service + ":" + s.handle), s.service + ": " + s.handle, s.confidence, [])) }
        return out
    }

    /// Signals recorded for a field (for policy decisions).
    public func signals(_ ref: FieldRef) -> [String] {
        switch ref {
        case .givenName: return givenName?.signals ?? []
        case .familyName: return familyName?.signals ?? []
        case .cjkName: return cjkName?.signals ?? []
        case .company: return company?.signals ?? []
        case .companyCJK: return companyCJK?.signals ?? []
        case .jobTitle: return jobTitle?.signals ?? []
        case .jobTitleCJK: return jobTitleCJK?.signals ?? []
        case .department: return department?.signals ?? []
        case .departmentCJK: return departmentCJK?.signals ?? []
        case .phone(let k): return phones.first { $0.e164 == k }?.signals ?? []
        case .email(let k): return emails.first { $0.value == k }?.signals ?? []
        case .website(let k): return websites.first { $0.value == k }?.signals ?? []
        case .address(let k): return addresses.first { $0.matchKey == k }?.signals ?? []
        case .social: return []
        }
    }

    /// A reading the first model itself doubted (it listed alternatives) counts as settled only after an
    /// independent confirmation: a second opinion, the other side of the card, or the user.
    public func isSettled(_ ref: FieldRef) -> Bool {
        let s = signals(ref)
        return s.contains { $0.hasPrefix("second_opinion:agree") || $0.hasPrefix("second_opinion:picked") || $0 == "user_review" || $0 == "cross_side_agree" }
    }

    /// Removes a field (used when a value is held back for review).
    public mutating func remove(_ ref: FieldRef) {
        switch ref {
        case .givenName: givenName = nil
        case .familyName: familyName = nil
        case .cjkName: cjkName = nil
        case .company: company = nil
        case .companyCJK: companyCJK = nil
        case .jobTitle: jobTitle = nil
        case .jobTitleCJK: jobTitleCJK = nil
        case .department: department = nil
        case .departmentCJK: departmentCJK = nil
        case .phone(let v): phones.removeAll { $0.e164 == v }
        case .email(let v): emails.removeAll { $0.value == v }
        case .website(let v): websites.removeAll { $0.value == v }
        case .address(let v): addresses.removeAll { $0.matchKey == v }
        case .social(let v): social.removeAll { $0.service + ":" + $0.handle == v }
        }
    }

    /// Applies a reviewed value for a field. `value == nil` means "leave empty".
    public mutating func resolve(_ ref: FieldRef, with value: String?, original: ContactDraft) {
        remove(ref)
        guard let value, !value.isEmpty else { return }
        let dv = DraftValue(value: value, confidence: 1, sources: [], signals: ["user_review"])
        switch ref {
        case .givenName: givenName = dv
        case .familyName: familyName = dv
        case .cjkName: cjkName = dv
        case .company: company = dv
        case .companyCJK: companyCJK = dv
        case .jobTitle: jobTitle = dv
        case .jobTitleCJK: jobTitleCJK = dv
        case .department: department = dv
        case .departmentCJK: departmentCJK = dv
        case .phone(let e164):
            var p = original.phones.first { $0.e164 == e164 } ?? DraftPhone(kind: .work, e164: e164, printed: value, confidence: 1)
            let region = p.e164.hasPrefix("+1") ? "CA" : nil
            if let n = PhoneNormalizer.normalize(value, regionHint: region) { p.e164 = n.e164; p.extensionNumber = n.extensionNumber ?? p.extensionNumber }
            p.printed = value; p.confidence = 1; p.signals.append("user_review")
            phones.append(p)
        case .email: emails.append(DraftValue(value: EmailValidator.repair(value), confidence: 1, signals: ["user_review"]))
        case .website: websites.append(dv)
        case .address(let key):
            var a = original.addresses.first { $0.matchKey == key } ?? DraftAddress(confidence: 1)
            a.formatted = value; a.confidence = 1; a.signals.append("user_review")
            addresses.append(a)
        case .social(let key):
            let service = String(key.split(separator: ":").first ?? "other")
            social.append(DraftSocial(service: service, handle: value, confidence: 1))
        }
    }
}

extension FieldRef {
    /// Parses the `description` form back (used for persisted review items).
    public init?(description s: String) {
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        let head = parts[0], tail = parts.count > 1 ? parts[1] : ""
        switch head {
        case "given_name": self = .givenName
        case "family_name": self = .familyName
        case "cjk_name": self = .cjkName
        case "company": self = .company
        case "company_cjk": self = .companyCJK
        case "job_title": self = .jobTitle
        case "job_title_cjk": self = .jobTitleCJK
        case "department": self = .department
        case "department_cjk": self = .departmentCJK
        case "phone": self = .phone(tail)
        case "email": self = .email(tail)
        case "website": self = .website(tail)
        case "address": self = .address(tail)
        case "social": self = .social(tail)
        default: return nil
        }
    }
}

extension ContactDraft {
    /// Reads the value + confidence for a single-valued or keyed field.
    public func current(_ ref: FieldRef) -> (value: String, confidence: Double, alternatives: [String])? {
        func dv(_ v: DraftValue?) -> (String, Double, [String])? { v.map { ($0.value, $0.confidence, $0.alternatives) } }
        switch ref {
        case .givenName: return dv(givenName)
        case .familyName: return dv(familyName)
        case .cjkName: return dv(cjkName)
        case .company: return dv(company)
        case .companyCJK: return dv(companyCJK)
        case .jobTitle: return dv(jobTitle)
        case .jobTitleCJK: return dv(jobTitleCJK)
        case .department: return dv(department)
        case .departmentCJK: return dv(departmentCJK)
        case .phone(let k): return phones.first { $0.e164 == k }.map { ($0.printed, $0.confidence, $0.alternatives) }
        case .email(let k): return dv(emails.first { $0.value == k })
        case .website(let k): return dv(websites.first { $0.value == k })
        case .address(let k): return addresses.first { $0.matchKey == k }.map { ($0.formatted ?? $0.street ?? "", $0.confidence, []) }
        case .social(let k): return social.first { $0.service + ":" + $0.handle == k }.map { ($0.handle, $0.confidence, []) }
        }
    }

    /// Updates value/confidence after a second opinion. Returns the (possibly re-keyed) ref.
    @discardableResult
    public mutating func setVerified(_ ref: FieldRef, value: String, confidence: Double, signal: String, regionHint: String) -> FieldRef {
        func upd(_ v: inout DraftValue?) {
            guard var x = v else { return }
            if x.value != value { x.alternatives = Array(Set(x.alternatives + [x.value]).subtracting([value])).sorted() }
            x.value = value; x.confidence = confidence; x.signals.append(signal); v = x
        }
        switch ref {
        case .givenName: upd(&givenName)
        case .familyName: upd(&familyName)
        case .cjkName: upd(&cjkName)
        case .company: upd(&company)
        case .companyCJK: upd(&companyCJK)
        case .jobTitle: upd(&jobTitle)
        case .jobTitleCJK: upd(&jobTitleCJK)
        case .department: upd(&department)
        case .departmentCJK: upd(&departmentCJK)
        case .phone(let k):
            guard let i = phones.firstIndex(where: { $0.e164 == k }) else { return ref }
            var p = phones[i]
            // Re-read numbers are normalised in the region of the number being verified, not the device default.
            let hint = PhoneNormalizer.region(ofE164: p.e164) ?? regionHint
            if let n = PhoneNormalizer.normalize(value, regionHint: hint), n.e164 != p.e164 {
                p.alternatives = Array(Set(p.alternatives + [p.printed])).sorted()
                p.e164 = n.e164; p.printed = value; p.isValid = n.isValid
                if let e = n.extensionNumber { p.extensionNumber = e }
            }
            p.confidence = confidence; p.signals.append(signal); phones[i] = p
            return .phone(p.e164)
        case .email(let k):
            guard let i = emails.firstIndex(where: { $0.value == k }) else { return ref }
            let repaired = EmailValidator.repair(value)
            var e = emails[i]
            if e.value != repaired { e.alternatives = Array(Set(e.alternatives + [e.value]).subtracting([repaired])).sorted() }
            e.value = repaired; e.confidence = confidence; e.signals.append(signal); emails[i] = e
            return .email(repaired)
        case .website(let k):
            guard let i = websites.firstIndex(where: { $0.value == k }) else { return ref }
            websites[i].value = value.lowercased(); websites[i].confidence = confidence; websites[i].signals.append(signal)
            return .website(websites[i].value)
        case .address(let k):
            // Addresses are confirmed or rejected as a whole; the printed text is kept.
            guard let i = addresses.firstIndex(where: { $0.matchKey == k }) else { return ref }
            addresses[i].confidence = confidence; addresses[i].signals.append(signal)
            return ref
        case .social:
            return ref
        }
        return ref
    }

    /// A draft containing only one field of `self` (used to patch an existing contact after review).
    public func only(_ ref: FieldRef) -> ContactDraft {
        var d = ContactDraft(id: id, photoIDs: photoIDs)
        switch ref {
        case .givenName: d.givenName = givenName
        case .familyName: d.familyName = familyName
        case .cjkName: d.cjkName = cjkName
        case .company: d.company = company
        case .companyCJK: d.companyCJK = companyCJK
        case .jobTitle: d.jobTitle = jobTitle
        case .jobTitleCJK: d.jobTitleCJK = jobTitleCJK
        case .department: d.department = department
        case .departmentCJK: d.departmentCJK = departmentCJK
        case .phone(let k): d.phones = phones.filter { $0.e164 == k }
        case .email(let k): d.emails = emails.filter { $0.value == k }
        case .website(let k): d.websites = websites.filter { $0.value == k }
        case .address(let k): d.addresses = addresses.filter { $0.matchKey == k }
        case .social(let k): d.social = social.filter { $0.service + ":" + $0.handle == k }
        }
        return d
    }
}
