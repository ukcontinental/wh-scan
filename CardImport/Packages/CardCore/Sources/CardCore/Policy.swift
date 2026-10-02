import Foundation

public struct PolicyConfig: Codable, Sendable {
    /// Name, phone and email must reach this to be written without review.
    public var autoAcceptCritical = 0.90
    /// Company, title, address, website, department, social.
    public var autoAcceptOther = 0.85
    /// Below this the value is treated as noise: not written, not asked, logged in the audit.
    public var dropBelow = 0.30
    public init() {}

    /// Fields whose reading the model doubted (alternatives listed) need an independent confirmation.
    public var alternativesNeedConfirmation = true

    /// True when this value may be written without review.
    public func accepts(_ ref: FieldRef, confidence: Double, alternatives: [String], in draft: ContactDraft) -> Bool {
        guard confidence >= threshold(for: ref) else { return false }
        if alternativesNeedConfirmation && !CardScorer.realAlternatives(alternatives, to: draft.current(ref)?.value ?? "").isEmpty
            && !draft.isSettled(ref) { return false }
        return true
    }

    func threshold(for ref: FieldRef) -> Double {
        switch ref.kind {
        case .personName, .phone, .email: return autoAcceptCritical
        default: return autoAcceptOther
        }
    }
}

public enum ReviewKind: String, Codable, Sendable {
    case field        // pick the right reading of one field
    case grouping     // which person does this back side belong to
    case duplicate    // is this the same person as an existing contact
    case conflict     // existing contact has a different company/title: update or keep
}

public struct ReviewItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var personID: String
    public var kind: ReviewKind
    /// FieldRef description for `.field`, field name for `.conflict`.
    public var field: String?
    public var question: String
    /// Candidate answers, best first. The UI always adds "leave empty"/"skip".
    public var candidates: [String]
    public var photoIDs: [String]
    public var existingContactID: String?
    /// When true the person's contact is not written until this item is resolved.
    public var blocking: Bool
    public var resolved: Bool
    public var answer: String?

    public init(id: String, personID: String, kind: ReviewKind, field: String? = nil, question: String, candidates: [String],
                photoIDs: [String], existingContactID: String? = nil, blocking: Bool) {
        self.id = id; self.personID = personID; self.kind = kind; self.field = field; self.question = question
        self.candidates = candidates; self.photoIDs = photoIDs; self.existingContactID = existingContactID
        self.blocking = blocking; self.resolved = false; self.answer = nil
    }
}

public struct PolicyOutcome: Codable, Sendable {
    /// What can be written now (held/dropped fields removed).
    public var writable: ContactDraft
    public var held: [String]
    public var dropped: [String]
    public var review: [ReviewItem]
    public var blocking: Bool { review.contains { $0.blocking } }
}

/// Field-level auto-accept policy: only uncertain fields go to review, never the whole card.
public struct ReviewPolicy: Sendable {
    public var config: PolicyConfig
    public init(config: PolicyConfig = PolicyConfig()) { self.config = config }

    static func label(_ ref: FieldRef) -> String {
        switch ref {
        case .givenName: return "名字 First name"
        case .familyName: return "姓氏 Last name"
        case .cjkName: return "中文姓名"
        case .company: return "公司 Company"
        case .companyCJK: return "公司（中文）"
        case .jobTitle: return "職稱 Job title"
        case .jobTitleCJK: return "職稱（中文）"
        case .department: return "部門 Department"
        case .departmentCJK: return "部門（中文）"
        case .phone: return "電話 Phone"
        case .email: return "Email"
        case .website: return "網站 Website"
        case .address: return "地址 Address"
        case .social: return "社群帳號"
        }
    }

    public func evaluate(_ draft: ContactDraft) -> PolicyOutcome {
        var writable = draft
        var held: [String] = [], dropped: [String] = [], review: [ReviewItem] = []
        var heldName = false
        for (ref, value, conf, alts) in draft.allFields() {
            if config.accepts(ref, confidence: conf, alternatives: alts, in: draft) { continue }
            writable.remove(ref)
            if conf < config.dropBelow && alts.isEmpty {
                dropped.append("\(ref)=\(value)@\(String(format: "%.2f", conf))")
                continue
            }
            held.append(ref.description)
            if ref.isNameField { heldName = true }
            var candidates: [String] = []
            for c in [value] + alts where !candidates.contains(c) { candidates.append(c) }
            review.append(ReviewItem(id: "\(draft.id)#\(ref)", personID: draft.id, kind: .field, field: ref.description,
                                     question: "\(Self.label(ref))：哪一個正確？", candidates: candidates, photoIDs: draft.photoIDs,
                                     blocking: false))
        }
        // A contact whose identity is uncertain must not be written yet: block only when no name survives.
        if heldName && !writable.hasPersonName {
            for i in review.indices where review[i].field.map({ $0.contains("name") }) ?? false { review[i].blocking = true }
        }
        // Nothing identifying at all (no name, no company, no phone/email) → hold everything.
        if !writable.hasPersonName && writable.company == nil && writable.companyCJK == nil && !writable.hasAnyContactMethod && !review.isEmpty {
            for i in review.indices { review[i].blocking = true }
        }
        return PolicyOutcome(writable: writable, held: held, dropped: dropped, review: review)
    }
}
