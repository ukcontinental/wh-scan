import Foundation

public enum PhotoStatus: String, Codable, Sendable {
    case pending       // not yet recognised (or waiting to be retried after a transient error)
    case recognized
    case failed        // gave up on this photo; the rest of the batch continued
}

public struct PhotoRecord: Codable, Hashable, Sendable {
    public var id: String
    public var index: Int
    public var captureDate: Date?
    public var visual: VisualSignature?
    public var status: PhotoStatus
    public var attempts: Int
    public var lastError: String?
    public var ocr: OCRResult?
    public var extraction: ExtractedCard?
    public var model: String?
    public var usage: TokenUsage
    public var seconds: Double
    /// Temporary image already deleted.
    public var imageDeleted: Bool

    public init(id: String, index: Int, captureDate: Date? = nil, visual: VisualSignature? = nil) {
        self.id = id; self.index = index; self.captureDate = captureDate; self.visual = visual
        status = .pending; attempts = 0; usage = TokenUsage(); seconds = 0; imageDeleted = false
    }
}

public enum PersonStatus: String, Codable, Sendable {
    case pending
    case created
    case updated
    case alreadyExists
    case needsReview     // blocked: nothing written yet
    case ignored         // no contact data (decorative back) or user chose to ignore
    case failed
}

public struct PersonRecord: Codable, Hashable, Sendable {
    public var id: String
    public var photoIDs: [String]
    public var status: PersonStatus
    public var draft: ContactDraft?
    /// Draft as it was before any held fields were removed (for review answers).
    public var fullDraft: ContactDraft?
    public var duplicate: DuplicateAssessment?
    public var contactIdentifier: String?
    public var held: [String]
    public var dropped: [String]
    public var verifiedFields: [String]
    public var lastError: String?

    public init(id: String, photoIDs: [String]) {
        self.id = id; self.photoIDs = photoIDs; status = .pending
        held = []; dropped = []; verifiedFields = []
    }
}

public enum BatchPhase: String, Codable, Sendable {
    case recognizing, grouping, finalizing, done
    case pausedOffline     // no network: resumes automatically next time
    case pausedAuth        // API key rejected: user must fix the key once
}

public struct LogEntry: Codable, Hashable, Sendable {
    public var at: Date
    public var message: String
}

public struct BatchSummary: Codable, Hashable, Sendable {
    public var photos = 0
    public var peopleDetected = 0
    public var created = 0
    public var updated = 0
    public var alreadyExisted = 0
    public var needsReviewPeople = 0
    public var openReviewItems = 0
    public var failedPhotos = 0
    public var ignoredPhotos = 0
    public var duplicatesFound = 0
    public var costUSD = 0.0
    public var seconds = 0.0
    public init() {}
}

public struct BatchState: Codable, Sendable {
    public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var source: String
    public var phase: BatchPhase
    public var photos: [PhotoRecord]
    public var people: [PersonRecord]
    public var grouping: GroupingResult?
    public var review: [ReviewItem]
    public var usage: TokenUsage
    public var log: [LogEntry]
    public var processingSeconds: Double

    public init(id: String = UUID().uuidString, source: String, photos: [PhotoRecord]) {
        self.id = id; createdAt = Date(); updatedAt = Date(); self.source = source; phase = .recognizing
        self.photos = photos; people = []; review = []; usage = TokenUsage(); log = []; processingSeconds = 0
    }

    public var summary: BatchSummary {
        var s = BatchSummary()
        s.photos = photos.count
        let real = people.filter { $0.status != .ignored }
        s.peopleDetected = real.count
        s.created = people.filter { $0.status == .created }.count
        s.updated = people.filter { $0.status == .updated }.count
        s.alreadyExisted = people.filter { $0.status == .alreadyExists }.count
        s.duplicatesFound = people.filter { [.updated, .alreadyExists].contains($0.status) || $0.duplicate?.verdict == .uncertain }.count
        let open = review.filter { !$0.resolved }
        s.openReviewItems = open.count
        s.needsReviewPeople = Set(open.map(\.personID)).count
        s.failedPhotos = photos.filter { $0.status == .failed }.count
        s.ignoredPhotos = grouping?.empty.count ?? 0
        s.costUSD = usage.costUSD
        s.seconds = processingSeconds
        return s
    }

    mutating func note(_ m: String) {
        log.append(LogEntry(at: Date(), message: m))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}

/// Crash-safe persistence: one JSON file per batch, written atomically after every step.
public actor BatchStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(_ id: String) -> URL { directory.appendingPathComponent("batch-\(id).json") }

    public func save(_ state: BatchState) throws {
        var s = state
        s.updatedAt = Date()
        let data = try CardJSON.encoder().encode(s)
        try data.write(to: url(s.id), options: .atomic)
    }

    public func load(_ id: String) throws -> BatchState {
        try CardJSON.decoder().decode(BatchState.self, from: Data(contentsOf: url(id)))
    }

    /// Batches that were interrupted (crash, kill, offline) and should be resumed.
    public func unfinished() -> [BatchState] {
        all().filter { $0.phase != .done }
    }

    public func all() -> [BatchState] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("batch-") }
            .compactMap { try? CardJSON.decoder().decode(BatchState.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Removes finished batch logs older than `days`.
    public func prune(olderThanDays days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for b in all() where b.phase == .done && b.updatedAt < cutoff { try? FileManager.default.removeItem(at: url(b.id)) }
    }
}
