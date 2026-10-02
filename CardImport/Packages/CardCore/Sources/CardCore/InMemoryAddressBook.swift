import Foundation

/// Address-book stand-in for tests and the benchmark (CNContactStore on device).
public actor InMemoryAddressBook: ContactIndex, ContactWriter {
    public struct Stored: Codable, Sendable {
        public var identifier: String
        public var snapshot: ExistingContact
        public var draft: ContactDraft?
        public var preexisting: Bool
    }

    public private(set) var contacts: [Stored] = []
    public private(set) var createCalls = 0
    public private(set) var updateCalls = 0
    /// Simulates a crash right after a save, before the batch state is persisted.
    public var failNextCreateAfterSaving = false

    public init(existing: [ExistingContact] = []) {
        contacts = existing.map { Stored(identifier: $0.identifier, snapshot: $0, draft: nil, preexisting: true) }
    }

    public func candidates(for draft: ContactDraft) async throws -> [ExistingContact] { contacts.map(\.snapshot) }

    public static func snapshot(id: String, _ d: ContactDraft) -> ExistingContact {
        ExistingContact(identifier: id, givenName: d.givenName?.value ?? (d.cjkName.map { NameUtil.splitCJK($0.value).given } ?? ""),
                        familyName: d.familyName?.value ?? (d.cjkName.map { NameUtil.splitCJK($0.value).family } ?? ""),
                        nickname: (d.givenName != nil || d.familyName != nil) ? (d.cjkName?.value ?? "") : "",
                        organization: d.company?.value ?? d.companyCJK?.value ?? "", jobTitle: d.jobTitle?.value ?? d.jobTitleCJK?.value ?? "",
                        phones: d.phones.map(\.e164), emails: d.emails.map(\.value), urls: d.websites.map(\.value))
    }

    public func create(_ draft: ContactDraft) async throws -> String {
        createCalls += 1
        let id = "mem-\(contacts.count + 1)"
        contacts.append(Stored(identifier: id, snapshot: Self.snapshot(id: id, draft), draft: draft, preexisting: false))
        if failNextCreateAfterSaving {
            failNextCreateAfterSaving = false
            throw CocoaErrorLike.simulatedCrash
        }
        return id
    }

    public func update(identifier: String, with draft: ContactDraft, mode: WriteMode) async throws {
        updateCalls += 1
        guard let i = contacts.firstIndex(where: { $0.identifier == identifier }) else { throw CocoaErrorLike.notFound }
        var base = contacts[i].draft ?? ContactDraft(id: identifier, photoIDs: [])
        func setIfEmpty(_ kp: WritableKeyPath<ContactDraft, DraftValue?>) {
            if let v = draft[keyPath: kp] { if base[keyPath: kp] == nil || mode == .overwriteSingleValued { base[keyPath: kp] = v } }
        }
        for kp in [\ContactDraft.givenName, \.familyName, \.cjkName, \.company, \.companyCJK, \.jobTitle, \.jobTitleCJK, \.department] { setIfEmpty(kp) }
        for p in draft.phones where !base.phones.contains(where: { $0.e164 == p.e164 }) { base.phones.append(p) }
        for e in draft.emails where !base.emails.contains(where: { $0.value == e.value }) { base.emails.append(e) }
        for w in draft.websites where !base.websites.contains(where: { $0.value == w.value }) { base.websites.append(w) }
        for a in draft.addresses where !base.addresses.contains(where: { $0.matchKey == a.matchKey }) { base.addresses.append(a) }
        for s in draft.social where !base.social.contains(where: { $0.handle == s.handle }) { base.social.append(s) }
        var snap = Self.snapshot(id: identifier, base)
        if contacts[i].preexisting {
            let old = contacts[i].snapshot
            snap.phones = Array(Set(old.phones + snap.phones)).sorted()
            snap.emails = Array(Set(old.emails + snap.emails)).sorted()
            if mode == .additive {
                if !old.organization.isEmpty { snap.organization = old.organization }
                if !old.jobTitle.isEmpty { snap.jobTitle = old.jobTitle }
                if !old.givenName.isEmpty { snap.givenName = old.givenName; snap.familyName = old.familyName }
            }
        }
        contacts[i].draft = base
        contacts[i].snapshot = snap
    }

    public enum CocoaErrorLike: Error { case simulatedCrash, notFound }
}
