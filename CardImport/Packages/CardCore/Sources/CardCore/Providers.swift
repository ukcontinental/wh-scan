import Foundation

// MARK: - Pipeline seams (implemented with Apple frameworks on iOS, with stand-ins in tests/benchmark)

public protocol OCRProvider: Sendable {
    func recognize(_ image: ImagePayload) async throws -> OCRResult
}

public struct ExtractionOutput: Sendable {
    public var card: ExtractedCard
    public var usage: TokenUsage
    public var model: String
    public init(card: ExtractedCard, usage: TokenUsage = TokenUsage(), model: String) {
        self.card = card; self.usage = usage; self.model = model
    }
}

public protocol CardExtractor: Sendable {
    func extract(image: ImagePayload, ocr: OCRResult?) async throws -> ExtractionOutput
}

public struct VerifierAnswer: Sendable {
    public var value: String?
    public var confidence: Double
    public var usage: TokenUsage
    public init(value: String?, confidence: Double, usage: TokenUsage = TokenUsage()) {
        self.value = value; self.confidence = confidence; self.usage = usage
    }
}

public protocol FieldVerifier: Sendable {
    func verify(fieldLabel: String, candidates: [String], images: [ImagePayload], ocrHint: [String]) async throws -> VerifierAnswer
}

public struct GroupingAnswer: Sendable {
    public var photoID: String
    public var group: Int?
    public var confidence: Double
}

public protocol GroupingResolver: Sendable {
    func resolve(groups: [ContactDraft], unassigned: [(photoID: String, draft: ContactDraft, captureDate: Date?)]) async throws -> ([GroupingAnswer], TokenUsage)
}

public enum WriteMode: String, Codable, Sendable {
    /// Add missing values only; never change existing ones.
    case additive
    /// Replace single-valued fields (company, title) with the draft's values; still never deletes anything.
    case overwriteSingleValued
}

public protocol ContactWriter: Sendable {
    /// Creates a contact and returns its identifier.
    func create(_ draft: ContactDraft) async throws -> String
    func update(identifier: String, with draft: ContactDraft, mode: WriteMode) async throws
}

public protocol ImageStore: Sendable {
    func load(_ photoID: String) async throws -> ImagePayload
    func delete(_ photoID: String) async
}

// MARK: - Claude implementations

public struct ClaudeExtractor: CardExtractor {
    public let client: ClaudeClient
    public init(client: ClaudeClient) { self.client = client }

    public func extract(image: ImagePayload, ocr: OCRResult?) async throws -> ExtractionOutput {
        let r = try await client.structured(model: client.config.extractionModel, effort: client.config.extractionEffort,
                                            system: Prompts.extractionSystem, userText: Prompts.extractionUser(ocr: ocr),
                                            images: [image], schema: Prompts.extractionSchema)
        let data = try JSONSerialization.data(withJSONObject: r.json)
        do {
            let card = try CardJSON.llmDecoder().decode(ExtractedCard.self, from: data)
            return ExtractionOutput(card: card, usage: r.usage, model: r.servedBy)
        } catch {
            throw LLMError.badOutput("schema mismatch: \(error)")
        }
    }
}

public struct ClaudeFieldVerifier: FieldVerifier {
    public let client: ClaudeClient
    public init(client: ClaudeClient) { self.client = client }

    public func verify(fieldLabel: String, candidates: [String], images: [ImagePayload], ocrHint: [String]) async throws -> VerifierAnswer {
        let r = try await client.structured(model: client.config.verifierModel, effort: client.config.verifierEffort,
                                            system: Prompts.verifySystem,
                                            userText: Prompts.verifyUser(fieldLabel: fieldLabel, candidates: candidates, ocrHint: ocrHint),
                                            images: images, schema: Prompts.verifySchema, maxTokens: 4000)
        let v = r.json["value"] as? String
        let c = (r.json["confidence"] as? Double) ?? (r.json["confidence"] as? NSNumber)?.doubleValue ?? 0.5
        return VerifierAnswer(value: (v?.isEmpty ?? true) ? nil : v, confidence: c, usage: r.usage)
    }
}

public struct ClaudeGroupingResolver: GroupingResolver {
    public let client: ClaudeClient
    public init(client: ClaudeClient) { self.client = client }

    static func summary(_ d: ContactDraft) -> [String: Any] {
        var o: [String: Any] = [:]
        o["name"] = d.displayName
        if let c = d.company?.value ?? d.companyCJK?.value { o["company"] = c }
        o["phones"] = d.phones.map { "\($0.kind.rawValue) \($0.e164)" }
        o["emails"] = d.emails.map(\.value)
        o["websites"] = d.websites.map(\.value)
        o["addresses"] = d.addresses.compactMap { $0.formatted ?? $0.street }
        return o
    }

    public func resolve(groups: [ContactDraft], unassigned: [(photoID: String, draft: ContactDraft, captureDate: Date?)]) async throws -> ([GroupingAnswer], TokenUsage) {
        let fmt = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "groups": groups.enumerated().map { (i, d) in ["group": i, "data": Self.summary(d)] as [String: Any] },
            "unassigned": unassigned.map { u in
                var o: [String: Any] = ["photo_id": u.photoID, "data": Self.summary(u.draft)]
                if let t = u.captureDate { o["captured_at"] = fmt.string(from: t) }
                return o
            },
        ]
        let r = try await client.structured(model: client.config.helperModel, effort: "high", system: Prompts.groupingSystem,
                                            userText: Prompts.jsonString(payload, pretty: true), images: [],
                                            schema: Prompts.groupingSchema, maxTokens: 4000)
        let list = r.json["assignments"] as? [[String: Any]] ?? []
        let answers = list.compactMap { a -> GroupingAnswer? in
            guard let id = a["photo_id"] as? String else { return nil }
            let c = (a["confidence"] as? Double) ?? (a["confidence"] as? NSNumber)?.doubleValue ?? 0
            return GroupingAnswer(photoID: id, group: a["group"] as? Int, confidence: c)
        }
        return (answers, r.usage)
    }
}

/// Turns a dictated note into labelled lines for the contact's Notes field.
public struct VoiceNoteStructurer: Sendable {
    public let client: ClaudeClient
    public init(client: ClaudeClient) { self.client = client }

    public func structure(transcript: String) async throws -> String {
        let r = try await client.structured(model: client.config.helperModel, effort: "low", system: Prompts.voiceNoteSystem,
                                            userText: transcript, images: [], schema: Prompts.voiceNoteSchema, maxTokens: 2000)
        return Self.format(r.json, transcript: transcript)
    }

    public static func format(_ j: [String: Any], transcript: String) -> String {
        var lines: [String] = []
        func add(_ label: String, _ key: String) {
            if let v = j[key] as? String, !v.isEmpty { lines.append("\(label): \(v)") }
        }
        add("Met at", "met_at"); add("Event", "event"); add("Date", "date_mentioned"); add("Industry", "industry")
        add("Appearance", "appearance")
        if let i = j["interests"] as? [String], !i.isEmpty { lines.append("Interests: " + i.joined(separator: ", ")) }
        add("Follow-up", "follow_up")
        if let o = j["other"] as? [String], !o.isEmpty { lines.append("Other: " + o.joined(separator: "; ")) }
        lines.append("Voice note: \(transcript)")
        return lines.joined(separator: "\n")
    }
}
