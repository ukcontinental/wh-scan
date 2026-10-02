import XCTest
@testable import CardCore

/// Regression tests for the independent code review findings.
final class ReviewFindingsTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("rf-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func processor(_ cards: [String: ExtractedCard], book: InMemoryAddressBook, ocr: [String: OCRResult] = [:]) -> BatchProcessor {
        BatchProcessor(store: BatchStore(directory: dir), images: FakeImages(), ocr: FakeOCR(byID: ocr), extractor: FakeExtractor(cards),
                       verifier: nil, resolver: nil, index: book, writer: book)
    }

    // #2: a review answer for a non-NANP number keeps its country.
    func testPhoneAnswerKeepsCountry() {
        var original = ContactDraft(id: "x", photoIDs: [])
        original.phones = [DraftPhone(kind: .work, e164: "+886223456789", printed: "(02) 2345-6789", confidence: 0.5)]
        var d = ContactDraft(id: "x", photoIDs: [])
        d.resolve(.phone("+886223456789"), with: "(02) 2345-6788", original: original)
        XCTAssertEqual(d.phones.first?.e164, "+886223456788")
        XCTAssertEqual(d.phones.first?.isValid, true)
    }

    // #6: a corrected invalid number is accepted; all-empty answers never create a blank contact.
    func testCorrectedInvalidPhoneIsWritten() async {
        let card = ExtractedCard(phones: [ExtractedPhone(kind: .mobile, number: "416-155-0137", confidence: 0.95)])
        let book = InMemoryAddressBook()
        let p = processor(["x": card], book: book)
        var s = await p.run(BatchState(source: "t", photos: [PhotoRecord(id: "x", index: 0)]))
        let item = s.review.first { $0.field?.hasPrefix("phone") ?? false }
        XCTAssertNotNil(item)
        s = await p.answer(item!.id, with: "416-555-0137", in: s)
        let stored = await book.contacts
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.draft?.phones.first?.e164, "+14165550137")
    }

    func testAllEmptyAnswersDoNotCreateBlankContact() async {
        let card = ExtractedCard(phones: [ExtractedPhone(kind: .mobile, number: "416-155-0137", confidence: 0.95)])
        let book = InMemoryAddressBook()
        let p = processor(["x": card], book: book)
        var s = await p.run(BatchState(source: "t", photos: [PhotoRecord(id: "x", index: 0)]))
        for it in s.review where !it.resolved { s = await p.answer(it.id, with: nil, in: s) }
        let count = await book.contacts.count
        XCTAssertEqual(count, 0)
    }

    // #3: answering the same item twice (double tap) writes once.
    func testDoubleAnswerIsIdempotent() async {
        let existing = ExistingContact(identifier: "old", givenName: "John", familyName: "Chen", organization: "ABC Foods")
        let book = InMemoryAddressBook(existing: [existing])
        var card = F.johnFront()
        card.emails = []; card.phones = []; card.websites = []
        let p = processor(["x": card], book: book)
        let s = await p.run(BatchState(source: "t", photos: [PhotoRecord(id: "x", index: 0)]))
        guard let dup = s.review.first(where: { $0.kind == .duplicate }) else { return XCTFail("expected duplicate question \(s.review)") }
        let s1 = await p.answer(dup.id, with: "new|不是", in: s)
        _ = await p.answer(dup.id, with: "new|不是", in: s1)
        let creates = await book.createCalls
        XCTAssertEqual(creates, 1)
    }

    // #4: a contact written just before a crash is found again even without mobile/email.
    func testResumeAfterCrashWithoutMobileOrEmail() async {
        var card = F.johnFront()
        card.emails = []
        card.phones = [ExtractedPhone(kind: .work, number: "(416) 555-0100", confidence: 0.98, sourceText: "T (416) 555-0100")]
        let book = InMemoryAddressBook()
        await book.setFailNextCreate()
        let p = processor(["x": card], book: book)
        var s = await p.run(BatchState(source: "t", photos: [PhotoRecord(id: "x", index: 0)]))
        for i in s.people.indices where s.people[i].status == .failed { s.people[i].status = .writing }   // as persisted before the crash
        s.phase = .finalizing
        s = await p.run(s)
        let count = await book.contacts.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(s.people.first?.status, .alreadyExists)
    }

    // #5: attaching an orphan back to a not-yet-written person must not write that person's held fields.
    func testOrphanMergeKeepsHeldFieldsHeld() async {
        let book = InMemoryAddressBook()
        let p = processor([:], book: book)
        let full = CardScorer().score(F.obs("f", 0, F.johnFront(titleConf: 0.71)))
        let outcome = ReviewPolicy().evaluate(full)
        XCTAssertNil(outcome.writable.jobTitle)
        var john = PersonRecord(id: "p-f", photoIDs: ["f"])
        john.fullDraft = full; john.draft = outcome.writable; john.status = .needsReview
        var orphanDraft = CardScorer().score(F.obs("b", 1, F.johnBack(), F.johnBackOCR()))
        orphanDraft.id = "orphan-b"
        var orphan = PersonRecord(id: "orphan-b", photoIDs: ["b"])
        orphan.fullDraft = orphanDraft; orphan.draft = orphanDraft; orphan.status = .needsReview
        var s = BatchState(source: "t", photos: [PhotoRecord(id: "f", index: 0), PhotoRecord(id: "b", index: 1)])
        s.phase = .done
        s.people = [john, orphan]
        s.review = outcome.review.map { var r = $0; r.personID = "p-f"; return r }
        s.review.append(ReviewItem(id: "p-f#duplicate", personID: "p-f", kind: .duplicate, question: "?", candidates: ["same|", "new|"],
                                   photoIDs: ["f"], existingContactID: "zzz", blocking: true))
        s.review.append(ReviewItem(id: "orphan-b#grouping", personID: "orphan-b", kind: .grouping, question: "?",
                                   candidates: ["p-f|John", "separate|", "ignore|"], photoIDs: ["b"], blocking: true))
        s = await p.answer("orphan-b#grouping", with: "p-f|John", in: s)
        s = await p.answer("p-f#duplicate", with: "new|", in: s)
        let written = await book.contacts.first?.draft
        XCTAssertNotNil(written)
        XCTAssertNil(written?.jobTitle, "held job title must not be written by the merge")
        XCTAssertEqual(Set(written?.phones.map(\.e164) ?? []), ["+14165550137", "+14165550100", "+14165550199"])
        XCTAssertTrue(s.review.contains { $0.field == "job_title" && !$0.resolved })
    }

    // #7: a corrected address replaces the doubted structured parts.
    func testAddressAnswerDropsDoubtedParts() {
        var original = ContactDraft(id: "x", photoIDs: [])
        let a = DraftAddress(street: "12O Front St", city: "Toronto", region: "ON", postalCode: "M5J 2M2", formatted: "12O Front St, Toronto", confidence: 0.5)
        original.addresses = [a]
        var d = ContactDraft(id: "x", photoIDs: [])
        d.resolve(.address(a.matchKey), with: "120 Front St W, Toronto, ON M5J 2M2", original: original)
        XCTAssertEqual(d.addresses.first?.street, "120 Front St W, Toronto, ON M5J 2M2")
        XCTAssertNil(d.addresses.first?.postalCode)
    }

    // #9: same number with and without extension are separate entries.
    func testExtensionIsPartOfPhoneIdentity() {
        var d = ContactDraft(id: "x", photoIDs: [])
        d.givenName = DraftValue(value: "A", confidence: 0.99)
        d.phones = [DraftPhone(kind: .work, e164: "+14165550100", printed: "416-555-0100 ext 204", extensionNumber: "204", confidence: 0.99),
                    DraftPhone(kind: .main, e164: "+14165550100", printed: "416-555-0100", confidence: 0.6)]
        let out = ReviewPolicy().evaluate(d)
        XCTAssertEqual(out.writable.phones.count, 1)
        XCTAssertEqual(out.writable.phones.first?.extensionNumber, "204")
        XCTAssertEqual(out.review.count, 1)
    }

    // #10: the dial-string form written to Contacts reads back as number + extension.
    func testCommaExtensionReadsBack() {
        let n = PhoneNormalizer.normalize("+14165550100,204", regionHint: "CA")
        XCTAssertEqual(n?.e164, "+14165550100")
        XCTAssertEqual(n?.extensionNumber, "204")
    }

    // #13: "name" inside an email/website must not make the contact blocking.
    func testHostnameIsNotANameField() {
        var d = ContactDraft(id: "x", photoIDs: [])
        d.givenName = DraftValue(value: "A", confidence: 0.4)
        d.company = DraftValue(value: "Hostname Ltd.", confidence: 0.99)
        d.emails = [DraftValue(value: "hr@hostname.com", confidence: 0.5)]
        let out = ReviewPolicy().evaluate(d)
        let emailItem = out.review.first { $0.field?.hasPrefix("email") ?? false }
        XCTAssertEqual(emailItem?.blocking, false)
        XCTAssertEqual(out.review.first { $0.field == "given_name" }?.blocking, true)
    }

    // #1: no Contacts access pauses the batch (people stay pending, images kept), then resumes.
    func testContactsUnavailablePausesInsteadOfFailing() async {
        let store = LockedAddressBook()
        let images = FakeImages()
        let p = BatchProcessor(store: BatchStore(directory: dir), images: images, ocr: FakeOCR(byID: ["x": F.johnOCR()]),
                               extractor: FakeExtractor(["x": F.johnFront()]), verifier: nil, resolver: nil, index: store, writer: store)
        var s = await p.run(BatchState(source: "t", photos: [PhotoRecord(id: "x", index: 0)]))
        XCTAssertEqual(s.phase, .pausedContacts)
        XCTAssertEqual(s.people.first?.status, .pending)
        let deleted = await images.deleted
        XCTAssertTrue(deleted.isEmpty)
        await store.allow()
        s = await p.run(s)
        XCTAssertEqual(s.phase, .done)
        XCTAssertEqual(s.people.first?.status, .created)
    }
}

/// Address book that refuses access until allowed (simulates missing Contacts permission).
actor LockedAddressBook: ContactIndex, ContactWriter {
    var allowed = false
    let inner: InMemoryAddressBook
    init() { inner = InMemoryAddressBook() }
    func allow() { allowed = true }
    func candidates(for draft: ContactDraft) async throws -> [ExistingContact] {
        guard allowed else { throw ContactStoreError.notAuthorized }
        return try await inner.candidates(for: draft)
    }
    func create(_ draft: ContactDraft) async throws -> String {
        guard allowed else { throw ContactStoreError.notAuthorized }
        return try await inner.create(draft)
    }
    func update(identifier: String, with draft: ContactDraft, mode: WriteMode) async throws {
        guard allowed else { throw ContactStoreError.notAuthorized }
        try await inner.update(identifier: identifier, with: draft, mode: mode)
    }
}

final class LeaseTests: XCTestCase {
    func testLeaseBlocksOtherProcessUntilExpiry() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lease-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BatchStore(directory: dir)
        let b = BatchState(source: "share", photos: [PhotoRecord(id: "x", index: 0)])
        try await store.save(b)
        let ext = await store.acquireLease(b.id, owner: "extension", ttl: 60)
        XCTAssertTrue(ext)
        let app = await store.acquireLease(b.id, owner: "app")
        XCTAssertFalse(app)
        let resumable = await store.resumable(owner: "app")
        XCTAssertTrue(resumable.isEmpty)
        await store.releaseLease(b.id, owner: "extension")
        let app2 = await store.acquireLease(b.id, owner: "app")
        XCTAssertTrue(app2)
        // Expired lease (crashed extension) does not block.
        _ = await store.acquireLease(b.id, owner: "extension", ttl: -1)
        let resumable2 = await store.resumable(owner: "app")
        XCTAssertEqual(resumable2.count, 1)
    }
}
