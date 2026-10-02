import Foundation

// MARK: - Extraction output (one photo = one side of one card)

/// A single recognised value with its confidence in [0, 1].
public struct FieldValue: Codable, Hashable, Sendable {
    public var value: String
    public var confidence: Double
    /// Other plausible readings (OCR ambiguity such as 0/O, 1/l, 8/B).
    public var alternatives: [String]
    /// Text exactly as printed on the card.
    public var sourceText: String

    public init(_ value: String, confidence: Double, alternatives: [String] = [], sourceText: String = "") {
        self.value = value
        self.confidence = confidence
        self.alternatives = alternatives
        self.sourceText = sourceText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(String.self, forKey: .value)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        alternatives = try c.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
    }
}

public enum CardSide: String, Codable, Sendable {
    case front, back, unknown
}

public struct ExtractedName: Codable, Hashable, Sendable {
    public var given: FieldValue?
    public var family: FieldValue?
    public var cjkFull: FieldValue?
    public var prefix: FieldValue?
    public var suffix: FieldValue?

    public init(given: FieldValue? = nil, family: FieldValue? = nil, cjkFull: FieldValue? = nil,
                prefix: FieldValue? = nil, suffix: FieldValue? = nil) {
        self.given = given; self.family = family; self.cjkFull = cjkFull
        self.prefix = prefix; self.suffix = suffix
    }

    public var isEmpty: Bool { given == nil && family == nil && cjkFull == nil }
}

public enum PhoneKind: String, Codable, Sendable, CaseIterable {
    case mobile, work, fax, main, other
}

public struct ExtractedPhone: Codable, Hashable, Sendable {
    public var kind: PhoneKind
    public var number: String
    public var `extension`: String?
    public var countryHint: String?
    public var confidence: Double
    public var alternatives: [String]
    public var sourceText: String

    public init(kind: PhoneKind, number: String, extension ext: String? = nil, countryHint: String? = nil,
                confidence: Double, alternatives: [String] = [], sourceText: String = "") {
        self.kind = kind; self.number = number; self.extension = ext; self.countryHint = countryHint
        self.confidence = confidence; self.alternatives = alternatives; self.sourceText = sourceText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(PhoneKind.self, forKey: .kind)) ?? .other
        number = try c.decode(String.self, forKey: .number)
        `extension` = try c.decodeIfPresent(String.self, forKey: .extension)
        countryHint = try c.decodeIfPresent(String.self, forKey: .countryHint)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        alternatives = try c.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
    }
}

public struct ExtractedEmail: Codable, Hashable, Sendable {
    public var address: String
    public var confidence: Double
    public var alternatives: [String]
    public var sourceText: String

    public init(address: String, confidence: Double, alternatives: [String] = [], sourceText: String = "") {
        self.address = address; self.confidence = confidence
        self.alternatives = alternatives; self.sourceText = sourceText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        alternatives = try c.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
    }
}

public struct ExtractedWebsite: Codable, Hashable, Sendable {
    public var url: String
    public var confidence: Double

    public init(url: String, confidence: Double) { self.url = url; self.confidence = confidence }
}

public struct ExtractedAddress: Codable, Hashable, Sendable {
    public var street: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?
    public var country: String?
    public var formatted: String?
    public var confidence: Double

    public init(street: String? = nil, city: String? = nil, region: String? = nil, postalCode: String? = nil,
                country: String? = nil, formatted: String? = nil, confidence: Double) {
        self.street = street; self.city = city; self.region = region; self.postalCode = postalCode
        self.country = country; self.formatted = formatted; self.confidence = confidence
    }
}

public struct ExtractedSocial: Codable, Hashable, Sendable {
    public var service: String
    public var handle: String
    public var confidence: Double

    public init(service: String, handle: String, confidence: Double) {
        self.service = service; self.handle = handle; self.confidence = confidence
    }
}

public struct Evidence: Codable, Hashable, Sendable {
    public var ignoredText: [String]
    public var hasPersonPhoto: Bool
    public var hasQrCode: Bool
    public var overallConfidence: Double
    public var concerns: [String]

    public init(ignoredText: [String] = [], hasPersonPhoto: Bool = false, hasQrCode: Bool = false,
                overallConfidence: Double = 0.5, concerns: [String] = []) {
        self.ignoredText = ignoredText; self.hasPersonPhoto = hasPersonPhoto; self.hasQrCode = hasQrCode
        self.overallConfidence = overallConfidence; self.concerns = concerns
    }
}

/// Structured recognition result for one photo (one side of one card).
public struct ExtractedCard: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var cardSide: CardSide
    public var isBusinessCard: Bool
    public var languageHint: [String]
    public var name: ExtractedName
    public var company: FieldValue?
    public var companyCjk: FieldValue?
    public var jobTitle: FieldValue?
    public var jobTitleCjk: FieldValue?
    public var department: FieldValue?
    public var phones: [ExtractedPhone]
    public var emails: [ExtractedEmail]
    public var websites: [ExtractedWebsite]
    public var addresses: [ExtractedAddress]
    public var social: [ExtractedSocial]
    public var notesOnCard: String?
    public var evidence: Evidence

    public init(cardSide: CardSide = .unknown, isBusinessCard: Bool = true, languageHint: [String] = [],
                name: ExtractedName = ExtractedName(), company: FieldValue? = nil, companyCjk: FieldValue? = nil,
                jobTitle: FieldValue? = nil, jobTitleCjk: FieldValue? = nil, department: FieldValue? = nil,
                phones: [ExtractedPhone] = [], emails: [ExtractedEmail] = [], websites: [ExtractedWebsite] = [],
                addresses: [ExtractedAddress] = [], social: [ExtractedSocial] = [], notesOnCard: String? = nil,
                evidence: Evidence = Evidence()) {
        self.schemaVersion = 1
        self.cardSide = cardSide; self.isBusinessCard = isBusinessCard; self.languageHint = languageHint
        self.name = name; self.company = company; self.companyCjk = companyCjk
        self.jobTitle = jobTitle; self.jobTitleCjk = jobTitleCjk; self.department = department
        self.phones = phones; self.emails = emails; self.websites = websites; self.addresses = addresses
        self.social = social; self.notesOnCard = notesOnCard; self.evidence = evidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        cardSide = (try? c.decode(CardSide.self, forKey: .cardSide)) ?? .unknown
        isBusinessCard = try c.decodeIfPresent(Bool.self, forKey: .isBusinessCard) ?? true
        languageHint = try c.decodeIfPresent([String].self, forKey: .languageHint) ?? []
        name = try c.decodeIfPresent(ExtractedName.self, forKey: .name) ?? ExtractedName()
        company = try c.decodeIfPresent(FieldValue.self, forKey: .company)
        companyCjk = try c.decodeIfPresent(FieldValue.self, forKey: .companyCjk)
        jobTitle = try c.decodeIfPresent(FieldValue.self, forKey: .jobTitle)
        jobTitleCjk = try c.decodeIfPresent(FieldValue.self, forKey: .jobTitleCjk)
        department = try c.decodeIfPresent(FieldValue.self, forKey: .department)
        phones = try c.decodeIfPresent([ExtractedPhone].self, forKey: .phones) ?? []
        emails = try c.decodeIfPresent([ExtractedEmail].self, forKey: .emails) ?? []
        websites = try c.decodeIfPresent([ExtractedWebsite].self, forKey: .websites) ?? []
        addresses = try c.decodeIfPresent([ExtractedAddress].self, forKey: .addresses) ?? []
        social = try c.decodeIfPresent([ExtractedSocial].self, forKey: .social) ?? []
        notesOnCard = try c.decodeIfPresent(String.self, forKey: .notesOnCard)
        evidence = try c.decodeIfPresent(Evidence.self, forKey: .evidence) ?? Evidence()
    }

    /// True when the side carries no usable contact information at all.
    public var hasNoContactData: Bool {
        name.isEmpty && company == nil && companyCjk == nil && phones.isEmpty && emails.isEmpty
            && websites.isEmpty && addresses.isEmpty && social.isEmpty
    }
}

// MARK: - OCR (on-device, Apple Vision on iPhone; tesseract in the Linux benchmark)

public struct OCRLine: Codable, Hashable, Sendable {
    public var text: String
    public var confidence: Double
    /// Normalised bounding box (x, y, width, height) in [0,1], origin top-left.
    public var box: [Double]?

    public init(text: String, confidence: Double, box: [Double]? = nil) {
        self.text = text; self.confidence = confidence; self.box = box
    }
}

public struct OCRResult: Codable, Hashable, Sendable {
    public var engine: String
    public var lines: [OCRLine]

    public init(engine: String, lines: [OCRLine]) { self.engine = engine; self.lines = lines }

    public var fullText: String { lines.map(\.text).joined(separator: "\n") }
}

/// Cheap visual features computed on-device, used for front/back matching.
public struct VisualSignature: Codable, Hashable, Sendable {
    /// Coarse colour histogram (e.g. 12 hue buckets + 3 grey buckets), L1 normalised.
    public var colorHistogram: [Double]
    /// Card aspect ratio (long / short side) if a card rectangle was detected.
    public var aspectRatio: Double?

    public init(colorHistogram: [Double], aspectRatio: Double? = nil) {
        self.colorHistogram = colorHistogram; self.aspectRatio = aspectRatio
    }
}

// MARK: - Coders

public enum CardJSON {
    /// Decoder for model output (snake_case keys, as in the published JSON schema).
    public static func llmDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Encoder producing the snake_case form of an ExtractedCard (same shape the model returns).
    public static func llmEncoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Persistence (batch state, audit log): Swift property names verbatim so round-trips are lossless.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
