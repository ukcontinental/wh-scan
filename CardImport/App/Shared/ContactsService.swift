import Foundation
import Contacts
import CardCore

/// CNContactStore-backed address book: duplicate lookup + create/update.
final class ContactsService: ContactIndex, ContactWriter, @unchecked Sendable {
    let store = CNContactStore()
    var nameStyle: NameStyle = AppSettings.nameStyle
    var writeNotes: Bool = AppSettings.contactsNotesEntitled

    static var authorized: Bool {
        let s = CNContactStore.authorizationStatus(for: .contacts)
        if s == .authorized { return true }
        if #available(iOS 18.0, *), s == .limited { return true }
        return false
    }

    static var isLimited: Bool {
        if #available(iOS 18.0, *) { return CNContactStore.authorizationStatus(for: .contacts) == .limited }
        return false
    }

    func requestAccess() async -> Bool {
        if Self.authorized { return true }
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    var keys: [CNKeyDescriptor] {
        var k: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                                    CNContactJobTitleKey, CNContactDepartmentNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
                                    CNContactUrlAddressesKey, CNContactPostalAddressesKey, CNContactSocialProfilesKey,
                                    CNContactInstantMessageAddressesKey, CNContactNamePrefixKey, CNContactNameSuffixKey,
                                    CNContactTypeKey, CNContactIdentifierKey].map { $0 as CNKeyDescriptor }
        if writeNotes { k.append(CNContactNoteKey as CNKeyDescriptor) }
        return k
    }

    // MARK: ContactIndex

    func candidates(for d: ContactDraft) async throws -> [ExistingContact] {
        var found: [String: CNContact] = [:]
        func fetch(_ p: NSPredicate) {
            if let r = try? store.unifiedContacts(matching: p, keysToFetch: keys) { for c in r { found[c.identifier] = c } }
        }
        for e in d.emails { fetch(CNContact.predicateForContacts(matchingEmailAddress: e.value)) }
        for p in d.phones { fetch(CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: p.e164))) }
        let latin = [d.givenName?.value, d.familyName?.value].compactMap { $0 }.joined(separator: " ")
        if !latin.isEmpty { fetch(CNContact.predicateForContacts(matchingName: latin)) }
        if let cjk = d.cjkName?.value { fetch(CNContact.predicateForContacts(matchingName: cjk)) }
        return found.values.map(Self.snapshot)
    }

    static func snapshot(_ c: CNContact) -> ExistingContact {
        ExistingContact(identifier: c.identifier, givenName: c.givenName, familyName: c.familyName, nickname: c.nickname,
                        organization: c.organizationName, jobTitle: c.jobTitle,
                        phones: c.phoneNumbers.map { $0.value.stringValue }, emails: c.emailAddresses.map { $0.value as String },
                        urls: c.urlAddresses.map { $0.value as String })
    }

    // MARK: ContactWriter

    func create(_ draft: ContactDraft) async throws -> String {
        let c = CNMutableContact()
        apply(draft, to: c, mode: .overwriteSingleValued)
        let req = CNSaveRequest()
        req.add(c, toContainerWithIdentifier: nil)
        try store.execute(req)
        return c.identifier
    }

    func update(identifier: String, with draft: ContactDraft, mode: WriteMode) async throws {
        let existing = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        guard let m = existing.mutableCopy() as? CNMutableContact else { return }
        apply(draft, to: m, mode: mode)
        let req = CNSaveRequest()
        req.update(m)
        try store.execute(req)
    }

    func appendNote(_ text: String, to identifier: String) throws {
        guard writeNotes else { throw NSError(domain: "CardImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Contacts notes entitlement not enabled"]) }
        let existing = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        guard let m = existing.mutableCopy() as? CNMutableContact else { return }
        m.note = m.note.isEmpty ? text : m.note + "\n\n" + text
        let req = CNSaveRequest()
        req.update(m)
        try store.execute(req)
    }

    /// Maps a draft onto a contact. Never deletes existing values; `additive` never changes them either.
    func apply(_ d: ContactDraft, to c: CNMutableContact, mode: WriteMode) {
        func set(_ current: String, _ new: String?, _ assign: (String) -> Void) {
            guard let new, !new.isEmpty else { return }
            if current.isEmpty || mode == .overwriteSingleValued { assign(new) }
        }
        let latinGiven = d.givenName?.value, latinFamily = d.familyName?.value
        let cjk = d.cjkName?.value
        let hasLatin = latinGiven != nil || latinFamily != nil
        if let cjk, !hasLatin || nameStyle == .cjkFirst {
            let parts = NameUtil.splitCJK(cjk)
            set(c.familyName, parts.family) { c.familyName = $0 }
            set(c.givenName, parts.given) { c.givenName = $0 }
            if hasLatin { set(c.nickname, [latinGiven, latinFamily].compactMap { $0 }.joined(separator: " ")) { c.nickname = $0 } }
        } else {
            set(c.givenName, latinGiven) { c.givenName = $0 }
            set(c.familyName, latinFamily) { c.familyName = $0 }
            // Keep the Chinese name searchable without changing how the contact is listed.
            if let cjk { set(c.nickname, cjk) { c.nickname = $0 } }
        }
        set(c.namePrefix, d.namePrefix?.value) { c.namePrefix = $0 }
        set(c.nameSuffix, d.nameSuffix?.value) { c.nameSuffix = $0 }
        let org = [d.company?.value, d.companyCJK?.value].compactMap { $0 }.joined(separator: " / ")
        set(c.organizationName, org.isEmpty ? nil : org) { c.organizationName = $0 }
        let title = [d.jobTitle?.value, d.jobTitleCJK?.value].compactMap { $0 }.joined(separator: " / ")
        set(c.jobTitle, title.isEmpty ? nil : title) { c.jobTitle = $0 }
        set(c.departmentName, d.department?.value) { c.departmentName = $0 }
        if !d.hasPersonName && !org.isEmpty && c.givenName.isEmpty && c.familyName.isEmpty { c.contactType = .organization }

        let existingDigits = Set(c.phoneNumbers.map { TextNorm.digits($0.value.stringValue) })
        for p in d.phones {
            var value = p.e164
            if let ext = p.extensionNumber { value += ",\(ext)" }
            let digits = TextNorm.digits(p.e164)
            if existingDigits.contains(where: { $0.hasSuffix(String(digits.suffix(9))) }) { continue }
            let label: String
            switch p.kind {
            case .mobile: label = CNLabelPhoneNumberMobile
            case .fax: label = CNLabelPhoneNumberWorkFax
            case .main: label = CNLabelPhoneNumberMain
            case .work: label = CNLabelWork
            case .other: label = CNLabelOther
            }
            c.phoneNumbers.append(CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: value)))
        }
        let existingEmails = Set(c.emailAddresses.map { ($0.value as String).lowercased() })
        for e in d.emails where !existingEmails.contains(e.value) {
            c.emailAddresses.append(CNLabeledValue(label: CNLabelWork, value: e.value as NSString))
        }
        let existingURLs = Set(c.urlAddresses.compactMap { DomainUtil.host(fromURL: $0.value as String) })
        for w in d.websites where !(DomainUtil.host(fromURL: w.value).map(existingURLs.contains) ?? false) {
            c.urlAddresses.append(CNLabeledValue(label: CNLabelWork, value: w.value as NSString))
        }
        let existingStreets = Set(c.postalAddresses.map { TextNorm.alnum($0.value.street + $0.value.postalCode) })
        for a in d.addresses {
            let pa = CNMutablePostalAddress()
            pa.street = a.street ?? a.formatted ?? ""
            pa.city = a.city ?? ""
            pa.state = a.region ?? ""
            pa.postalCode = a.postalCode ?? ""
            pa.country = a.country ?? ""
            if let iso = a.isoCountry { pa.isoCountryCode = iso.lowercased() }
            if existingStreets.contains(TextNorm.alnum(pa.street + pa.postalCode)) { continue }
            c.postalAddresses.append(CNLabeledValue(label: CNLabelWork, value: pa))
        }
        for s in d.social {
            switch s.service {
            case "wechat", "line", "whatsapp":
                let service = ["wechat": "WeChat", "line": "LINE", "whatsapp": "WhatsApp"][s.service]!
                if c.instantMessageAddresses.contains(where: { $0.value.username == s.handle }) { continue }
                c.instantMessageAddresses.append(CNLabeledValue(label: CNLabelWork, value: CNInstantMessageAddress(username: s.handle, service: service)))
            default:
                let service: String
                switch s.service {
                case "linkedin": service = CNSocialProfileServiceLinkedIn
                case "facebook": service = CNSocialProfileServiceFacebook
                case "x": service = CNSocialProfileServiceTwitter
                default: service = s.service.capitalized
                }
                if c.socialProfiles.contains(where: { $0.value.username == s.handle }) { continue }
                c.socialProfiles.append(CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: s.handle, userIdentifier: nil, service: service)))
            }
        }
        if writeNotes, let notes = d.cardNotes, !notes.isEmpty, !c.note.contains(notes) {
            c.note = c.note.isEmpty ? "On card: \(notes)" : c.note + "\nOn card: \(notes)"
        }
    }
}
