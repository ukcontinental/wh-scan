import XCTest
@testable import CardCore

final class ScorerTests: XCTestCase {
    func testCleanCardPassesPolicy() {
        let d = CardScorer().score(F.obs("a", 0, F.johnFront(), F.johnOCR()))
        let out = ReviewPolicy().evaluate(d)
        XCTAssertTrue(out.review.isEmpty, "\(out.review.map(\.field))")
        XCTAssertEqual(out.writable.phones.first?.e164, "+14165550137")
        XCTAssertEqual(out.writable.phones.first?.kind, .mobile)
        XCTAssertGreaterThan(d.emails[0].confidence, 0.98)
    }

    func testOCRDisagreementLowersConfidence() {
        var card = F.johnFront()
        card.phones[0].number = "416-555-0187"   // the AI misread one digit
        let d = CardScorer().score(F.obs("a", 0, card, F.johnOCR()))
        XCTAssertLessThan(d.phones[0].confidence, 0.95)
    }

    func testSloganInCompanyIsPenalised() {
        var card = F.johnFront()
        card.company = F.fv("Your Trusted Partner in Frozen Foods Since 1985 Across Canada", 0.9)
        let d = CardScorer().score(F.obs("a", 0, card, nil))
        XCTAssertLessThan(d.company!.confidence, 0.85)
    }

    func testOnlyUncertainTitleGoesToReview() {
        let ocr = OCRResult(engine: "t", lines: F.johnOCR().lines.filter { $0.text != "Sales Manager" } + [OCRLine(text: "Sa1es Manaqer", confidence: 0.4)])
        let d = CardScorer().score(F.obs("a", 0, F.johnFront(titleConf: 0.71), ocr))
        let out = ReviewPolicy().evaluate(d)
        XCTAssertEqual(out.review.map(\.field), ["job_title"])
        XCTAssertFalse(out.blocking)
        XCTAssertNotNil(out.writable.givenName)
        XCTAssertNil(out.writable.jobTitle)
        XCTAssertEqual(out.review.first?.candidates, ["Sales Manager", "Sales Director"])
    }

    func testUncertainNameBlocks() {
        var card = F.johnFront()
        card.name = ExtractedName(given: F.fv("Jonh", 0.5), family: F.fv("Chen", 0.5))
        let d = CardScorer().score(F.obs("a", 0, card, nil))
        let out = ReviewPolicy().evaluate(d)
        XCTAssertTrue(out.blocking)
    }
}

final class GroupingTests: XCTestCase {
    func items(_ list: [(String, Int, ExtractedCard, OCRResult?, TimeInterval?)]) -> [(CardObservation, ContactDraft)] {
        list.map { let o = F.obs($0.0, $0.1, $0.2, $0.3, t: $0.4); return (o, CardScorer().score(o)) }
    }

    func testFrontBackPairedAndColleagueSeparate() {
        let r = FrontBackMatcher().group(items([
            ("john-front", 0, F.johnFront(), F.johnOCR(), 100), ("mary", 1, F.maryFront(), F.maryOCR(), 300),
            ("john-back", 2, F.johnBack(), F.johnBackOCR(), 108),
        ]))
        XCTAssertEqual(r.groups.count, 2)
        XCTAssertTrue(r.groups.contains(["john-front", "john-back"]), "\(r.groups) \(r.ambiguous)")
        XCTAssertTrue(r.groups.contains(["mary"]))
    }

    func testAmbiguousBackWithoutTimestamps() {
        // Same company, same office line on both colleagues' cards, no capture times → cannot tell.
        let r = FrontBackMatcher().group(items([
            ("john-front", 0, F.johnFront(), F.johnOCR(), nil), ("mary", 1, F.maryFront(), F.maryOCR(), nil),
            ("back", 5, F.johnBack(), F.johnBackOCR(), nil),
        ]))
        XCTAssertNotNil(r.ambiguous["back"], "\(r.groups)")
    }

    func testBilingualSidesMerge() {
        let r = FrontBackMatcher().group(items([("zh", 0, F.wangFrontZH(), nil, nil), ("en", 1, F.wangBackEN(), nil, nil)]))
        XCTAssertEqual(r.groups, [["zh", "en"]])
    }

    func testDifferentPeopleSameCompanyNeverMerge() {
        let e = FrontBackMatcher().pairEvidence((F.obs("a", 0, F.johnFront()), CardScorer().score(F.obs("a", 0, F.johnFront()))),
                                               (F.obs("b", 1, F.maryFront()), CardScorer().score(F.obs("b", 1, F.maryFront()))))
        XCTAssertTrue(e.conflict)
    }

    func testDecorativeBackIsEmpty() {
        let r = FrontBackMatcher().group(items([("a", 0, F.johnFront(), nil, nil), ("deco", 1, ExtractedCard(cardSide: .back), nil, nil)]))
        XCTAssertEqual(r.empty, ["deco"])
    }

    func testMergeBilingual() {
        let a = CardScorer().score(F.obs("zh", 0, F.wangFrontZH()))
        let b = CardScorer().score(F.obs("en", 1, F.wangBackEN()))
        let m = DraftMerger().merge(id: "p", drafts: [a, b])
        XCTAssertEqual(m.cjkName?.value, "王大明")
        XCTAssertEqual(m.givenName?.value, "David")
        XCTAssertEqual(m.phones.count, 1)
        XCTAssertEqual(m.phones[0].e164, "+886912345678")
        XCTAssertEqual(m.emails.count, 1)
        XCTAssertGreaterThan(m.emails[0].confidence, a.emails[0].confidence)
        XCTAssertEqual(m.companyCJK?.value, "大明食品股份有限公司")
        XCTAssertEqual(m.company?.value, "Da Ming Foods Co., Ltd.")
    }
}

final class DuplicateTests: XCTestCase {
    let draft = CardScorer().score(F.obs("a", 0, F.johnFront(), F.johnOCR()))

    func testSameEmailNoNewData() {
        let c = ExistingContact(identifier: "x", givenName: "John", familyName: "Chen", organization: "ABC Foods Ltd.",
                                jobTitle: "Sales Manager", phones: ["416 555 0137"], emails: ["john.chen@abcfoods.com"], urls: ["abcfoods.com"])
        XCTAssertEqual(DuplicateDetector().assess(draft, against: [c]).verdict, .alreadyExists)
    }

    func testSamePersonNewPhone() {
        let c = ExistingContact(identifier: "x", givenName: "John", familyName: "Chen", emails: ["john.chen@abcfoods.com"])
        let a = DuplicateDetector().assess(draft, against: [c])
        XCTAssertEqual(a.verdict, .update)
        XCTAssertTrue(a.additions.contains("phone:+14165550137"))
    }

    func testJobChangeIsConflict() {
        let c = ExistingContact(identifier: "x", givenName: "John", familyName: "Chen", organization: "XYZ Trading",
                                phones: ["(416) 555-0137"])
        let a = DuplicateDetector().assess(draft, against: [c])
        XCTAssertEqual(a.verdict, .updateWithConflicts)
        XCTAssertEqual(a.conflicts.first?.field, "organization")
    }

    func testNameOnlyIsNotEnough() {
        let c = ExistingContact(identifier: "x", givenName: "John", familyName: "Chen")
        XCTAssertEqual(DuplicateDetector().assess(draft, against: [c]).verdict, .new)
    }

    func testNamePlusCompanyIsUncertain() {
        let c = ExistingContact(identifier: "x", givenName: "John", familyName: "Chen", organization: "ABC Foods")
        XCTAssertEqual(DuplicateDetector().assess(draft, against: [c]).verdict, .uncertain)
    }

    func testDifferentPersonSharedOfficeLine() {
        let mary = CardScorer().score(F.obs("m", 0, F.maryFront()))
        let c = ExistingContact(identifier: "x", givenName: "Peter", familyName: "Ho", organization: "ABC Foods Ltd.", phones: ["416-555-0100"])
        XCTAssertEqual(DuplicateDetector().assess(mary, against: [c]).verdict, .new)
    }
}

final class BatchTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cardcore-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeState() -> BatchState {
        let ids = ["john-front", "mary", "john-back", "zh", "en"]
        let times: [TimeInterval] = [100, 300, 108, 500, 507]
        return BatchState(source: "test", photos: ids.enumerated().map { PhotoRecord(id: $1, index: $0, captureDate: Date(timeIntervalSince1970: times[$0])) })
    }

    func cards() -> [String: ExtractedCard] {
        ["john-front": F.johnFront(titleConf: 0.71), "mary": F.maryFront(), "john-back": F.johnBack(), "zh": F.wangFrontZH(), "en": F.wangBackEN()]
    }

    func ocr() -> FakeOCR {
        var john = F.johnOCR()
        john.lines = john.lines.filter { $0.text != "Sales Manager" } + [OCRLine(text: "Sa1es Manaqer", confidence: 0.4)]
        return FakeOCR(byID: ["john-front": john, "mary": F.maryOCR(), "john-back": F.johnBackOCR()])
    }

    func processor(_ ex: FakeExtractor, book: InMemoryAddressBook, verifier: FieldVerifier? = nil, images: FakeImages = FakeImages()) -> BatchProcessor {
        BatchProcessor(store: BatchStore(directory: dir), images: images, ocr: ocr(), extractor: ex, verifier: verifier,
                       resolver: nil, index: book, writer: book)
    }

    func testHappyPath() async throws {
        let book = InMemoryAddressBook()
        let images = FakeImages()
        let s = await processor(FakeExtractor(cards()), book: book, images: images).run(makeState())
        let sum = s.summary
        XCTAssertEqual(s.phase, .done)
        XCTAssertEqual(sum.photos, 5)
        XCTAssertEqual(sum.peopleDetected, 3)
        XCTAssertEqual(sum.created, 3)
        XCTAssertEqual(sum.openReviewItems, 1)               // only John's job title
        XCTAssertEqual(s.review.first?.field, "job_title")
        let created = await book.contacts
        XCTAssertEqual(created.count, 3)
        let john = created.first { $0.draft?.givenName?.value == "John" }!.draft!
        XCTAssertEqual(Set(john.phones.map(\.e164)), ["+14165550137", "+14165550100", "+14165550199"])
        XCTAssertNil(john.jobTitle)                            // held back, not guessed
        XCTAssertEqual(john.addresses.first?.postalCode, "M5J 2M2")
        // Images of fully finished people are deleted; John's stay until the review is answered.
        let deleted = await images.deleted
        XCTAssertEqual(deleted, ["mary", "zh", "en"])

        // Answer the one review question → contact patched, batch fully clean.
        let p = BatchProcessor(store: BatchStore(directory: dir), images: images, ocr: nil, extractor: FakeExtractor([:]), verifier: nil,
                               resolver: nil, index: book, writer: book)
        let s2 = await p.answer(s.review[0].id, with: "Sales Manager", in: s)
        XCTAssertEqual(s2.summary.openReviewItems, 0)
        let john2 = await book.contacts.first { $0.draft?.givenName?.value == "John" }!.draft!
        XCTAssertEqual(john2.jobTitle?.value, "Sales Manager")
        let deleted2 = await images.deleted
        XCTAssertEqual(deleted2.count, 5)
    }

    func testSecondOpinionResolvesWithoutUser() async throws {
        let book = InMemoryAddressBook()
        let verifier = FakeVerifier { label, cands in VerifierAnswer(value: "Sales Manager", confidence: 0.97) }
        let s = await processor(FakeExtractor(cards()), book: book, verifier: verifier).run(makeState())
        XCTAssertEqual(s.summary.openReviewItems, 0, "\(s.review)")
        XCTAssertEqual(s.summary.created, 3)
        let john = await book.contacts.first { $0.draft?.givenName?.value == "John" }!.draft!
        XCTAssertEqual(john.jobTitle?.value, "Sales Manager")
    }

    func testSecondOpinionDisagreementStaysInReview() async throws {
        let book = InMemoryAddressBook()
        let verifier = FakeVerifier { _, _ in VerifierAnswer(value: "Senior Sales Manager", confidence: 0.8) }
        let s = await processor(FakeExtractor(cards()), book: book, verifier: verifier).run(makeState())
        XCTAssertEqual(s.summary.openReviewItems, 1)
        XCTAssertTrue(s.review[0].candidates.contains("Senior Sales Manager"))
    }

    func testOnePermanentFailureDoesNotBlockBatch() async throws {
        let ex = FakeExtractor(cards()); ex.permanentFor = ["mary"]
        let book = InMemoryAddressBook()
        let s = await processor(ex, book: book).run(makeState())
        XCTAssertEqual(s.phase, .done)
        XCTAssertEqual(s.summary.failedPhotos, 1)
        XCTAssertEqual(s.summary.created, 2)
    }

    func testOfflinePausesThenResumes() async throws {
        let ex = FakeExtractor(cards()); ex.transientFor = Set(cards().keys)
        let book = InMemoryAddressBook()
        let s = await processor(ex, book: book).run(makeState())
        XCTAssertEqual(s.phase, .pausedOffline)
        XCTAssertEqual(s.summary.failedPhotos, 0)
        let created0 = await book.contacts.count
        XCTAssertEqual(created0, 0)
        // Network back: resume from the persisted state.
        ex.transientFor = []
        let saved = try await BatchStore(directory: dir).load(s.id)
        let s2 = await processor(ex, book: book).run(saved)
        XCTAssertEqual(s2.phase, .done)
        XCTAssertEqual(s2.summary.created, 3)
    }

    func testBadKeyPausesOnce() async throws {
        let ex = FakeExtractor(cards()); ex.unauthorized = true
        let s = await processor(ex, book: InMemoryAddressBook()).run(makeState())
        XCTAssertEqual(s.phase, .pausedAuth)
        XCTAssertLessThanOrEqual(ex.calls.count, 4)
    }

    func testCrashAfterSaveDoesNotDuplicate() async throws {
        let book = InMemoryAddressBook()
        await book.setFailNextCreate()
        let ex = FakeExtractor(cards())
        let s = await processor(ex, book: book).run(makeState())
        // The first create "crashed" after saving: that person is marked failed in this run…
        XCTAssertEqual(s.people.filter { $0.status == .failed }.count, 1)
        // …and re-running the person (as after an app relaunch) finds the saved contact instead of creating a second one.
        var again = s
        for i in again.people.indices where again.people[i].status == .failed { again.people[i].status = .pending }
        again.phase = .finalizing
        let s2 = await processor(ex, book: book).run(again)
        let count = await book.contacts.count
        XCTAssertEqual(count, 3)
        XCTAssertEqual(s2.people.filter { $0.status == .alreadyExists }.count, 1)
    }

    func testExistingContactIsUpdatedNotDuplicated() async throws {
        let existing = ExistingContact(identifier: "old-1", givenName: "Mary", familyName: "Lee", organization: "ABC Foods Ltd.",
                                       emails: ["mary.lee@abcfoods.com"])
        let book = InMemoryAddressBook(existing: [existing])
        let s = await processor(FakeExtractor(cards()), book: book).run(makeState())
        XCTAssertEqual(s.summary.updated, 1)
        XCTAssertEqual(s.summary.created, 2)
        let all = await book.contacts
        XCTAssertEqual(all.count, 3)
        let mary = all.first { $0.identifier == "old-1" }!
        XCTAssertTrue(mary.snapshot.phones.contains("+16475550142"))
    }
}

extension InMemoryAddressBook {
    func setFailNextCreate() { failNextCreateAfterSaving = true }
}
