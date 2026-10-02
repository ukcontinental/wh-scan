import Foundation

public struct BatchConfig: Sendable {
    public var maxConcurrentRecognitions = 4
    public var maxVerificationsPerPerson = 4
    public var defaultRegion = "CA"
    public var policy = PolicyConfig()
    public var grouping = GroupingConfig()
    public var confidence = ConfidenceModel()
    /// Delete temporary images once nothing refers to them any more.
    public var deleteImagesWhenDone = true
    /// Minimum resolver confidence to accept an LLM grouping decision.
    public var resolverAcceptConfidence = 0.85
    /// Stop after grouping (e.g. a share extension without Contacts access); the app finishes the batch later.
    public var stopBeforeWriting = false
    public init() {}
}

public struct BatchProgress: Sendable {
    public var phase: BatchPhase
    public var recognized: Int
    public var totalPhotos: Int
    public var peopleDone: Int
    public var peopleTotal: Int
}

/// Orchestrates one batch: recognise every photo (in parallel, independently), group sides into people,
/// verify uncertain fields, apply the field-level policy, de-duplicate against the address book and write.
/// Every step is persisted, so a crash / kill / network loss resumes where it stopped without duplicates.
public actor BatchProcessor {
    let store: BatchStore
    let images: ImageStore
    let ocr: OCRProvider?
    let extractor: CardExtractor
    let verifier: FieldVerifier?
    let resolver: GroupingResolver?
    let index: ContactIndex
    let writer: ContactWriter
    public let config: BatchConfig
    var progressHandler: (@Sendable (BatchProgress) -> Void)?

    public init(store: BatchStore, images: ImageStore, ocr: OCRProvider?, extractor: CardExtractor, verifier: FieldVerifier?,
                resolver: GroupingResolver?, index: ContactIndex, writer: ContactWriter, config: BatchConfig = BatchConfig()) {
        self.store = store; self.images = images; self.ocr = ocr; self.extractor = extractor; self.verifier = verifier
        self.resolver = resolver; self.index = index; self.writer = writer; self.config = config
    }

    public func onProgress(_ h: @escaping @Sendable (BatchProgress) -> Void) { progressHandler = h }

    var scorer: CardScorer { CardScorer(model: config.confidence, defaultRegion: config.defaultRegion) }

    func report(_ s: BatchState) {
        let done = s.people.filter { $0.status != .pending }.count
        progressHandler?(BatchProgress(phase: s.phase, recognized: s.photos.filter { $0.status != .pending }.count,
                                       totalPhotos: s.photos.count, peopleDone: done, peopleTotal: s.people.count))
    }

    func persist(_ s: BatchState) async {
        do { try await store.save(s) } catch { /* disk full etc.: keep going in memory */ }
        report(s)
    }

    // MARK: Run

    public func run(_ initial: BatchState) async -> BatchState {
        var s = initial
        let started = Date()
        if s.phase == .pausedOffline || s.phase == .pausedAuth {
            s.phase = s.people.isEmpty ? .recognizing : .finalizing
        }
        if s.phase == .recognizing {
            s = await recognize(s)
            if s.phase == .pausedOffline || s.phase == .pausedAuth {
                s.processingSeconds += Date().timeIntervalSince(started)
                await persist(s)
                return s
            }
            s.phase = .grouping
            await persist(s)
        }
        if s.phase == .grouping {
            s = await groupPeople(s)
            s.phase = .finalizing
            await persist(s)
        }
        if s.phase == .finalizing && config.stopBeforeWriting {
            s.processingSeconds += Date().timeIntervalSince(started)
            await persist(s)
            return s
        }
        if s.phase == .finalizing {
            s = await finalize(s)
        }
        s = refreshPhase(s)
        s.processingSeconds += Date().timeIntervalSince(started)
        await cleanupImages(&s)
        await persist(s)
        return s
    }

    func refreshPhase(_ s0: BatchState) -> BatchState {
        var s = s0
        guard s.phase == .finalizing || s.phase == .done else { return s }
        let pending = s.people.contains { $0.status == .pending }
        s.phase = pending ? .finalizing : .done
        return s
    }

    // MARK: Stage 1 — recognition (independent per photo)

    enum RecognitionOutcome: Sendable {
        case success(OCRResult?, ExtractionOutput, Double)
        case transient(String)
        case permanent(String)
        case auth(String)
    }

    nonisolated func recognizeOne(_ p: PhotoRecord) async -> RecognitionOutcome {
        let t0 = Date()
        do {
            let image = try await images.load(p.id)
            var ocrResult: OCRResult? = nil
            if let ocr { ocrResult = try? await ocr.recognize(image) }   // OCR failure is not fatal
            let out = try await extractor.extract(image: image, ocr: ocrResult)
            return .success(ocrResult, out, Date().timeIntervalSince(t0))
        } catch let e as LLMError {
            switch e {
            case .unauthorized(let m): return .auth(m)
            case .missingAPIKey: return .auth("missing API key")
            case .transient(let m): return .transient(m)
            default: return .permanent(e.description)
            }
        } catch {
            return .permanent(String(describing: error))
        }
    }

    func recognize(_ s0: BatchState) async -> BatchState {
        var s = s0
        s.phase = .recognizing
        let pending = s.photos.filter { $0.status == .pending }
        guard !pending.isEmpty else { return s }
        var successes = 0
        var transientIDs: [String: String] = [:]
        var authError: String? = nil

        await withTaskGroup(of: (String, RecognitionOutcome).self) { group in
            var queue = pending.makeIterator()
            for _ in 0..<max(1, config.maxConcurrentRecognitions) {
                guard let p = queue.next() else { break }
                group.addTask { (p.id, await self.recognizeOne(p)) }
            }
            while let (id, outcome) = await group.next() {
                guard let i = s.photos.firstIndex(where: { $0.id == id }) else { continue }
                s.photos[i].attempts += 1
                switch outcome {
                case .success(let o, let out, let secs):
                    s.photos[i].status = .recognized
                    s.photos[i].ocr = o
                    s.photos[i].extraction = out.card
                    s.photos[i].model = out.model
                    s.photos[i].usage = s.photos[i].usage + out.usage
                    s.photos[i].seconds += secs
                    s.photos[i].lastError = nil
                    s.usage = s.usage + out.usage
                    successes += 1
                case .transient(let m):
                    transientIDs[id] = m
                    s.photos[i].lastError = m
                case .permanent(let m):
                    s.photos[i].status = .failed
                    s.photos[i].lastError = m
                    s.note("photo \(id) failed: \(m)")
                case .auth(let m):
                    authError = m
                    s.photos[i].lastError = m
                }
                await persist(s)
                if authError != nil { group.cancelAll(); break }
                if let p = queue.next() { group.addTask { (p.id, await self.recognizeOne(p)) } }
            }
        }
        if let authError {
            s.phase = .pausedAuth
            s.note("API key rejected: \(authError)")
            return s
        }
        if !transientIDs.isEmpty {
            if successes == 0 {
                // Nothing got through: we are offline. Keep everything pending and resume later.
                s.phase = .pausedOffline
                s.note("offline: \(transientIDs.count) photos waiting")
                return s
            }
            // Partial outage: do not block the batch on a few photos.
            for (id, m) in transientIDs {
                if let i = s.photos.firstIndex(where: { $0.id == id }) {
                    s.photos[i].status = .failed
                    s.photos[i].lastError = "network: \(m)"
                }
            }
            s.note("\(transientIDs.count) photos failed after retries; the rest continued")
        }
        return s
    }

    // MARK: Stage 2 — grouping sides into people

    func observations(_ s: BatchState) -> [(CardObservation, ContactDraft)] {
        s.photos.filter { $0.status == .recognized && $0.extraction != nil }.map { p in
            let obs = CardObservation(photoID: p.id, index: p.index, captureDate: p.captureDate, extraction: p.extraction!,
                                      ocr: p.ocr, visual: p.visual)
            return (obs, scorer.score(obs))
        }
    }

    func groupPeople(_ s0: BatchState) async -> BatchState {
        var s = s0
        let items = observations(s)
        let matcher = FrontBackMatcher(config: config.grouping)
        var result = matcher.group(items)
        let merger = DraftMerger(model: config.confidence)
        let draftOf: [String: ContactDraft] = Dictionary(uniqueKeysWithValues: items.map { ($0.0.photoID, $0.1) })
        func merged(_ ids: [String]) -> ContactDraft { merger.merge(id: "p-" + (ids.first ?? UUID().uuidString), drafts: ids.compactMap { draftOf[$0] }) }

        // Ask the text-only resolver about ambiguous sides before bothering the user.
        var orphans = Array(result.ambiguous.keys).sorted()
        if !orphans.isEmpty, let resolver {
            let groupDrafts = result.groups.map(merged)
            let unassigned = orphans.compactMap { id -> (photoID: String, draft: ContactDraft, captureDate: Date?)? in
                guard let d = draftOf[id] else { return nil }
                return (id, d, s.photos.first { $0.id == id }?.captureDate)
            }
            if let (answers, usage) = try? await resolver.resolve(groups: groupDrafts, unassigned: unassigned) {
                s.usage = s.usage + usage
                for a in answers where a.confidence >= config.resolverAcceptConfidence {
                    guard let g = a.group, g >= 0, g < result.groups.count, let candidates = result.ambiguous[a.photoID], candidates.contains(g) else { continue }
                    result.groups[g].append(a.photoID)
                    result.ambiguous[a.photoID] = nil
                    s.note("resolver attached \(a.photoID) to group \(g) (\(a.confidence))")
                }
            }
            orphans = Array(result.ambiguous.keys).sorted()
        }
        // Groups contain only assigned photos; ambiguous photos are not in any group yet.
        s.grouping = result
        s.people = result.groups.map { ids in
            var p = PersonRecord(id: "p-" + ids[0], photoIDs: ids)
            let d = merged(ids)
            p.draft = d; p.fullDraft = d
            return p
        }
        for id in orphans {
            guard let d = draftOf[id] else { continue }
            var p = PersonRecord(id: "orphan-" + id, photoIDs: [id])
            var od = d; od.id = p.id
            p.draft = od; p.fullDraft = od
            p.status = .needsReview
            let options = (result.ambiguous[id] ?? []).compactMap { gi -> String? in
                gi < s.people.count ? "\(s.people[gi].id)|\(s.people[gi].draft?.displayName ?? "?")" : nil
            }
            s.review.append(ReviewItem(id: "\(p.id)#grouping", personID: p.id, kind: .grouping,
                                       question: "這張背面屬於哪一位？", candidates: options + ["separate|另建一位聯絡人", "ignore|忽略這張"],
                                       photoIDs: [id], blocking: true))
            s.people.append(p)
        }
        s.note("grouping: \(s.photos.count) photos → \(result.groups.count) people, \(orphans.count) ambiguous, \(result.empty.count) empty")
        return s
    }

    // MARK: Stage 3 — verify, decide, de-duplicate, write

    struct Prepared: Sendable {
        var personID: String
        var draft: ContactDraft
        var outcome: PolicyOutcome
        var verified: [String]
        var usage: TokenUsage
    }

    nonisolated func prepare(_ p: PersonRecord, photos: [PhotoRecord]) async -> Prepared {
        var draft = p.draft ?? ContactDraft(id: p.id, photoIDs: p.photoIDs)
        var usage = TokenUsage()
        var verified: [String] = []
        let policy = ReviewPolicy(config: config.policy)
        if let verifier {
            let first = policy.evaluate(draft)
            let candidates = draft.allFields().filter { ref, _, conf, alts in
                !config.policy.accepts(ref, confidence: conf, alternatives: alts, in: draft) && conf >= config.policy.dropBelow
                    && { if case .social = ref { return false }; return true }()
            }
            _ = first
            if !candidates.isEmpty {
                var imgs: [ImagePayload] = []
                for id in p.photoIDs { if let i = try? await images.load(id) { imgs.append(i) } }
                let ocrLines = photos.filter { p.photoIDs.contains($0.id) }.flatMap { $0.ocr?.lines.map(\.text) ?? [] }
                let region = draft.phones.first.flatMap { $0.e164.hasPrefix("+886") ? "TW" : $0.e164.hasPrefix("+86") ? "CN" : nil } ?? config.defaultRegion
                for (ref, value, conf, alts) in candidates.prefix(config.maxVerificationsPerPerson) where !imgs.isEmpty {
                    let cands = [value] + alts
                    let label = ReviewPolicy.label(ref) + Self.verifyContext(ref, draft: draft)
                    let hints = ocrLines.filter { line in cands.contains { TextNorm.similarity(line, $0) >= 0.5 || (!TextNorm.digits($0).isEmpty && TextNorm.digits(line).contains(String(TextNorm.digits($0).suffix(4)))) } }
                    guard let ans = try? await verifier.verify(fieldLabel: label, candidates: cands, images: imgs,
                                                               ocrHint: Array(hints.prefix(6))) else { continue }
                    usage = usage + ans.usage
                    verified.append(ref.description)
                    // Exact comparison: variant characters (恆/恒, 着/著) are different values on a contact card.
                    let key: (String) -> String = { ref.kind == .phone ? TextNorm.digits(PhoneNormalizer.splitExtension($0).0) : TextNorm.alnum($0) }
                    if case .address = ref {
                        // Addresses: agreement = same numbers and mostly the same words.
                        guard let v = ans.value else { continue }
                        let sameDigits = Set(TextNorm.tokens(v).filter { $0.allSatisfy(\.isNumber) }) == Set(TextNorm.tokens(value).filter { $0.allSatisfy(\.isNumber) })
                        let model = config.confidence
                        if sameDigits && TextNorm.similarity(v, value) >= 0.75 {
                            draft.setVerified(ref, value: value, confidence: model.adjust(max(conf, ans.confidence * 0.9), deltas: [model.secondOpinionAgree]),
                                              signal: "second_opinion:agree", regionHint: region)
                        } else {
                            draft.setVerified(ref, value: value, confidence: model.adjust(conf, deltas: [model.secondOpinionDisagree]),
                                              signal: "second_opinion:disagree", regionHint: region)
                        }
                        continue
                    }
                    guard let v = ans.value else {
                        // Second reader says the field is not printed at all.
                        if ans.confidence >= 0.9 { draft.remove(ref) }
                        continue
                    }
                    let model = config.confidence
                    if key(v) == key(value) {
                        draft.setVerified(ref, value: value, confidence: model.adjust(max(conf, ans.confidence * 0.9), deltas: [model.secondOpinionAgree]),
                                          signal: "second_opinion:agree", regionHint: region)
                    } else if let alt = alts.first(where: { key($0) == key(v) }) {
                        // The second reader picked the first reader's alternative.
                        let altConf = max(1 - conf, 0.5)
                        draft.setVerified(ref, value: alt, confidence: model.adjust(min(altConf, ans.confidence), deltas: [model.secondOpinionAgree * 0.75]),
                                          signal: "second_opinion:picked_alternative", regionHint: region)
                    } else {
                        // Disagreement: keep the first reading, lower it, offer both in review.
                        draft.setVerified(ref, value: value, confidence: model.adjust(conf, deltas: [model.secondOpinionDisagree]),
                                          signal: "second_opinion:disagree", regionHint: region)
                        draft.addAlternative(v, to: ref)
                    }
                }
            }
        }
        return Prepared(personID: p.id, draft: draft, outcome: policy.evaluate(draft), verified: verified, usage: usage)
    }

    /// Tells the second reader WHICH value is meant when a card prints several of the same kind.
    nonisolated static func verifyContext(_ ref: FieldRef, draft: ContactDraft) -> String {
        switch ref {
        case .phone(let k):
            guard let p = draft.phones.first(where: { $0.e164 == k }) else { return "" }
            var s = " — the \(p.kind.rawValue) number"
            if let ext = p.extensionNumber { s += " (extension \(ext) printed with it)" }
            return s + "; the first reader saw it printed as “\(p.printed)”"
        case .address(let k):
            guard let a = draft.addresses.first(where: { $0.matchKey == k }) else { return "" }
            return " — the address the first reader read as “\(a.formatted ?? a.street ?? "")” (if several addresses are printed, read this same one)"
        case .email(let k):
            return " — the email address read as “\(k)”"
        default:
            return ""
        }
    }

    func finalize(_ s0: BatchState) async -> BatchState {
        var s = s0
        let todo = s.people.filter { $0.status == .pending }
        guard !todo.isEmpty else { return s }
        let photos = s.photos
        var prepared: [Prepared] = []
        await withTaskGroup(of: Prepared.self) { group in
            var queue = todo.makeIterator()
            for _ in 0..<max(1, config.maxConcurrentRecognitions) {
                guard let p = queue.next() else { break }
                group.addTask { await self.prepare(p, photos: photos) }
            }
            while let r = await group.next() {
                prepared.append(r)
                if let p = queue.next() { group.addTask { await self.prepare(p, photos: photos) } }
            }
        }
        // Writes are sequential so later people see earlier ones in the address book.
        for r in prepared.sorted(by: { a, b in (s.people.firstIndex { $0.id == a.personID } ?? 0) < (s.people.firstIndex { $0.id == b.personID } ?? 0) }) {
            guard let i = s.people.firstIndex(where: { $0.id == r.personID }) else { continue }
            s.usage = s.usage + r.usage
            s.people[i].fullDraft = r.draft
            s.people[i].verifiedFields = r.verified
            s.people[i].held = r.outcome.held
            s.people[i].dropped = r.outcome.dropped
            s.review.removeAll { $0.personID == r.personID && $0.kind == .field && !$0.resolved }
            s.review += r.outcome.review
            s.people[i].draft = r.outcome.writable
            if r.draft.isEmpty {
                s.people[i].status = .ignored
            } else if r.outcome.blocking {
                s.people[i].status = .needsReview
            } else {
                await commit(i, in: &s)
            }
            await persist(s)
        }
        return s
    }

    /// De-duplicates and writes person `i` (its `draft` is the writable part).
    func commit(_ i: Int, in s: inout BatchState) async {
        guard let draft = s.people[i].draft else { return }
        do {
            let candidates = try await index.candidates(for: draft)
            let a = DuplicateDetector(defaultRegion: config.defaultRegion).assess(draft, against: candidates)
            s.people[i].duplicate = a
            switch a.verdict {
            case .new:
                s.people[i].contactIdentifier = try await writer.create(draft)
                s.people[i].status = .created
            case .alreadyExists:
                s.people[i].contactIdentifier = a.match?.identifier
                s.people[i].status = .alreadyExists
            case .update, .updateWithConflicts:
                guard let id = a.match?.identifier else { break }
                try await writer.update(identifier: id, with: draft, mode: .additive)
                s.people[i].contactIdentifier = id
                s.people[i].status = .updated
                for c in a.conflicts {
                    s.review.append(ReviewItem(id: "\(s.people[i].id)#conflict-\(c.field)", personID: s.people[i].id, kind: .conflict,
                                               field: c.field, question: "\(c.field == "organization" ? "公司" : "職稱")不同：要更新嗎？",
                                               candidates: ["new|\(c.incoming)", "keep|\(c.existing)"], photoIDs: s.people[i].photoIDs,
                                               existingContactID: id, blocking: false))
                }
            case .uncertain:
                s.people[i].status = .needsReview
                let name = a.match?.displayName ?? "?"
                s.review.append(ReviewItem(id: "\(s.people[i].id)#duplicate", personID: s.people[i].id, kind: .duplicate,
                                           question: "和通訊錄裡的「\(name)」是同一人嗎？",
                                           candidates: ["same|是同一人（合併）", "new|不是，建立新聯絡人"], photoIDs: s.people[i].photoIDs,
                                           existingContactID: a.match?.identifier, blocking: true))
            }
        } catch {
            s.people[i].status = .failed
            s.people[i].lastError = String(describing: error)
            s.note("write failed for \(s.people[i].id): \(error)")
        }
    }

    // MARK: Review answers

    /// Applies the user's answer to one review item. `answer` is one of the item's candidates
    /// (for `.field` the chosen value, possibly edited), or nil for "leave empty / skip".
    public func answer(_ itemID: String, with answer: String?, in s0: BatchState) async -> BatchState {
        var s = s0
        guard let ri = s.review.firstIndex(where: { $0.id == itemID }) else { return s }
        s.review[ri].resolved = true
        s.review[ri].answer = answer
        let item = s.review[ri]
        guard let pi = s.people.firstIndex(where: { $0.id == item.personID }) else { await persist(s); return s }
        let key = answer.map { String($0.split(separator: "|").first ?? "") }

        switch item.kind {
        case .field:
            guard let f = item.field, let ref = FieldRef(description: f) else { break }
            let original = s.people[pi].fullDraft ?? s.people[pi].draft ?? ContactDraft(id: item.personID, photoIDs: item.photoIDs)
            if let id = s.people[pi].contactIdentifier, [.created, .updated, .alreadyExists].contains(s.people[pi].status) {
                var patch = ContactDraft(id: item.personID, photoIDs: item.photoIDs)
                patch.resolve(ref, with: answer, original: original)
                if !patch.hasNoFields {
                    do { try await writer.update(identifier: id, with: patch, mode: .additive) }
                    catch { s.note("update after review failed: \(error)") }
                }
                s.people[pi].draft?.resolve(ref, with: answer, original: original)
            } else {
                s.people[pi].draft?.resolve(ref, with: answer, original: original)
            }
        case .duplicate:
            if key == "same", let id = item.existingContactID, let d = s.people[pi].draft {
                do {
                    try await writer.update(identifier: id, with: d, mode: .additive)
                    s.people[pi].contactIdentifier = id
                    s.people[pi].status = .updated
                } catch { s.people[pi].status = .failed; s.people[pi].lastError = "\(error)" }
            } else if key == "new", let d = s.people[pi].draft {
                do {
                    s.people[pi].contactIdentifier = try await writer.create(d)
                    s.people[pi].status = .created
                } catch { s.people[pi].status = .failed; s.people[pi].lastError = "\(error)" }
            }
        case .conflict:
            if key == "new", let id = item.existingContactID, let f = item.field, let d = s.people[pi].draft {
                var patch = ContactDraft(id: d.id, photoIDs: d.photoIDs)
                if f == "organization" { patch.company = d.company ?? d.companyCJK } else { patch.jobTitle = d.jobTitle ?? d.jobTitleCJK }
                do { try await writer.update(identifier: id, with: patch, mode: .overwriteSingleValued) }
                catch { s.note("conflict update failed: \(error)") }
            }
        case .grouping:
            guard let key else { s.people[pi].status = .ignored; break }
            if key == "ignore" {
                s.people[pi].status = .ignored
            } else if key == "separate" {
                s.people[pi].status = .pending
            } else if let ti = s.people.firstIndex(where: { $0.id == key }), let orphan = s.people[pi].fullDraft {
                let merger = DraftMerger(model: config.confidence)
                let target = s.people[ti].fullDraft ?? s.people[ti].draft ?? ContactDraft(id: key, photoIDs: [])
                let combined = merger.merge(id: key, drafts: [target, orphan])
                s.people[pi].status = .ignored
                s.people[ti].photoIDs += s.people[pi].photoIDs
                if let id = s.people[ti].contactIdentifier {
                    // Already written: add only what the extra side contributes and passes the policy.
                    let extra = ReviewPolicy(config: config.policy).evaluate(orphan)
                    do { try await writer.update(identifier: id, with: extra.writable, mode: .additive) }
                    catch { s.note("merge update failed: \(error)") }
                    s.people[ti].fullDraft = combined
                } else {
                    s.people[ti].draft = combined; s.people[ti].fullDraft = combined
                    if s.people[ti].status != .needsReview { s.people[ti].status = .pending }
                }
            }
        }

        // A blocked person whose blocking questions are all answered can now be written.
        let stillBlocked = s.review.contains { $0.personID == item.personID && $0.blocking && !$0.resolved }
        if !stillBlocked && s.people[pi].status == .needsReview, let d = s.people[pi].draft {
            let outcome = ReviewPolicy(config: config.policy).evaluate(d)
            s.people[pi].draft = outcome.writable
            await commit(pi, in: &s)
        }
        if s.people.contains(where: { $0.status == .pending }) {
            s.phase = .finalizing
            s = await finalize(s)
        }
        s = refreshPhase(s)
        await cleanupImages(&s)
        await persist(s)
        return s
    }

    /// Photos that failed are re-run as a new batch (the address-book de-duplication prevents duplicates).
    public func retryBatch(forFailedPhotosOf s: BatchState) -> BatchState? {
        let failed = s.photos.filter { $0.status == .failed && !$0.imageDeleted }
        guard !failed.isEmpty else { return nil }
        let photos = failed.enumerated().map { (n, p) in PhotoRecord(id: p.id, index: n, captureDate: p.captureDate, visual: p.visual) }
        return BatchState(source: "retry:\(s.id)", photos: photos)
    }

    // MARK: Temporary image cleanup

    func cleanupImages(_ s: inout BatchState) async {
        guard config.deleteImagesWhenDone else { return }
        let openReviewPhotos = Set(s.review.filter { !$0.resolved }.flatMap(\.photoIDs))
        let pendingPeoplePhotos = Set(s.people.filter { $0.status == .pending }.flatMap(\.photoIDs))
        for i in s.photos.indices where !s.photos[i].imageDeleted {
            let p = s.photos[i]
            let keep = p.status == .pending || p.status == .failed || openReviewPhotos.contains(p.id) || pendingPeoplePhotos.contains(p.id)
                || s.phase == .pausedOffline || s.phase == .pausedAuth
            if !keep {
                await images.delete(p.id)
                s.photos[i].imageDeleted = true
            }
        }
    }
}

extension ContactDraft {
    mutating func addAlternative(_ v: String, to ref: FieldRef) {
        func add(_ x: inout DraftValue?) { if x != nil, x!.value != v, !x!.alternatives.contains(v) { x!.alternatives.append(v) } }
        switch ref {
        case .givenName: add(&givenName)
        case .familyName: add(&familyName)
        case .cjkName: add(&cjkName)
        case .company: add(&company)
        case .companyCJK: add(&companyCJK)
        case .jobTitle: add(&jobTitle)
        case .jobTitleCJK: add(&jobTitleCJK)
        case .department: add(&department)
        case .departmentCJK: add(&departmentCJK)
        case .phone(let k): if let i = phones.firstIndex(where: { $0.e164 == k }), !phones[i].alternatives.contains(v) { phones[i].alternatives.append(v) }
        case .email(let k): if let i = emails.firstIndex(where: { $0.value == k }), !emails[i].alternatives.contains(v) { emails[i].alternatives.append(v) }
        case .website(let k): if let i = websites.firstIndex(where: { $0.value == k }), !websites[i].alternatives.contains(v) { websites[i].alternatives.append(v) }
        case .address, .social: break
        }
    }
}
