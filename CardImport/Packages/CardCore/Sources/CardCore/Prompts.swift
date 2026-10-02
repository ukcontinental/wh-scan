import Foundation

/// Prompts and JSON schemas sent to the vision model. Kept in one place so the benchmark,
/// the iOS app and the docs all use exactly the same text.
public enum Prompts {
    public static let extractionSystem = """
    You read ONE photo of ONE side of a business card and return the contact information as JSON, so it can be \
    saved into the user's iPhone address book with no human checking. A wrong value saved silently is much worse \
    than an empty field, and a confidence that is too high is worse than one that is too low.

    Rules
    1. Transcribe only what is printed. Never invent, translate, complete or "fix" data. Missing → null or [].
       Only exceptions: phone country_hint and an address country may be inferred from a printed country code, \
    city or postal code.
    2. People: put Latin-script names in name.given / name.family and a CJK name exactly as printed in name.cjk_full \
    (family name first, no spaces). If both an English and a Chinese name of the SAME person are printed (e.g. \
    "王大明" and "David Wang"), fill both. "CHEN Ming-Hui" → family "Chen", given "Ming-Hui". Convert ALL-CAPS Latin \
    names to normal capitalisation ("JOHN SMITH" → "John Smith"). Prefix/suffix (Dr., PhD, CPA, P.Eng.) only if printed.
       Decide which line is the person by meaning and typography, not position: a company can contain a surname \
    ("Chan & Chan Trading") and a person can share a word with the company ("Morgan Lee" at "Morgan Consulting").
    3. company = the organisation's full name as printed (prefer the line with Ltd./Inc./Co./有限公司 over a logo \
    wordmark or abbreviation). Put the Chinese company name in company_cjk when both scripts are printed. A logo \
    wordmark that differs from the company name goes to evidence.ignored_text.
    4. job_title and department are separate. Bilingual titles/departments: Latin in job_title / department, CJK in \
    job_title_cjk / department_cjk. When a company, title or department is printed only in Chinese, put it only in \
    the *_cjk field and leave the Latin field null.
    5. phones: one entry per number. kind from the printed label: M/Mob/Cell/手機/行動 → mobile; T/Tel/Office/ \
    Direct/電話 → work; F/Fax/傳真 → fax; Main/總機/Toll-free → main. Without a label: Taiwan 09xx, China 1xx \
    (11 digits), Hong Kong numbers starting 5/6/9 → mobile, otherwise work. number = digits as printed including any \
    printed country code (+, spaces and dashes allowed); extension in extension (ext./x/分機/轉). source_text = the \
    whole printed line including its label.
    6. emails and websites exactly as printed, lower-case. Do not add "www" or "https".
    7. addresses: split into street (incl. unit/suite/floor), city, region (province/state/縣市), postal_code, \
    country; formatted = the full printed address on one line. For Chinese addresses keep the printed order \
    in formatted and still fill the parts you can identify.
    8. Ignore and list in evidence.ignored_text: slogans, taglines, certifications (ISO 9001, HACCP), product or \
    service lists, awards, decorative text, logo wordmarks, QR-code captions, icon-only social links. Never put \
    any of these into a field.
    9. social: only handles that are printed (LinkedIn, WeChat, LINE, WhatsApp, Instagram…).
    10. card_side = "front" if the person's name is on this side, otherwise "back". is_business_card = false if \
    the photo is not a business card at all.
    11. confidence = probability that the value is exactly right, character for character, AND in the right field:
       0.97–0.99 crisp and unambiguous, label or context confirms the field;
       0.90–0.96 legible, small doubt;
       0.60–0.89 some characters unclear (blur, glare, tiny font, 0/O, 1/l, 5/S, 8/B) or the field type is \
    debatable — then also give alternatives;
       below 0.60 a guess.
       Do not inflate. evidence.overall_confidence summarises the whole side.
    12. An on-device OCR transcript is supplied. It can contain errors and its line order may differ from the card. \
    Trust the image; use the transcript to double-check small digits and letters. If the image and the transcript \
    disagree on a character you cannot resolve, lower that field's confidence and list the other reading in \
    alternatives.
    13. evidence.concerns: short tags such as "two_people_on_card", "name_vs_company_ambiguous", "blurry_digits", \
    "partially_cut_off", "handwritten_changes".
    """

    public static func extractionUser(ocr: OCRResult?) -> String {
        var s = "Extract the contact information from this business-card photo."
        if let ocr, !ocr.lines.isEmpty {
            let lines = ocr.lines.prefix(80).map { "- " + $0.text }.joined(separator: "\n")
            s += "\n\nOn-device OCR transcript (\(ocr.engine), may contain errors):\n" + lines
        } else {
            s += "\n\n(No OCR transcript available.)"
        }
        return s
    }

    // MARK: Schemas (structured outputs: every property required, absent values are null)

    static func nullable(_ schema: [String: Any]) -> [String: Any] { ["anyOf": [schema, ["type": "null"]]] }
    static let str: [String: Any] = ["type": "string"]
    static let num: [String: Any] = ["type": "number"]
    static let bool: [String: Any] = ["type": "boolean"]
    static func arr(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
    static func obj(_ props: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
    }
    static func enumStr(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }

    static let fieldValue: [String: Any] = obj([
        "value": str, "confidence": num, "alternatives": arr(str), "source_text": str,
    ])

    public static var extractionSchema: [String: Any] {
        obj([
            "schema_version": ["type": "integer"],
            "card_side": enumStr(["front", "back", "unknown"]),
            "is_business_card": bool,
            "language_hint": arr(enumStr(["en", "zh-Hant", "zh-Hans", "ja", "ko", "other"])),
            "name": obj([
                "given": nullable(fieldValue), "family": nullable(fieldValue), "cjk_full": nullable(fieldValue),
                "prefix": nullable(fieldValue), "suffix": nullable(fieldValue),
            ]),
            "company": nullable(fieldValue),
            "company_cjk": nullable(fieldValue),
            "job_title": nullable(fieldValue),
            "job_title_cjk": nullable(fieldValue),
            "department": nullable(fieldValue),
            "department_cjk": nullable(fieldValue),
            "phones": arr(obj([
                "kind": enumStr(PhoneKind.allCases.map(\.rawValue)), "number": str, "extension": nullable(str),
                "country_hint": nullable(str), "confidence": num, "alternatives": arr(str), "source_text": str,
            ])),
            "emails": arr(obj(["address": str, "confidence": num, "alternatives": arr(str), "source_text": str])),
            "websites": arr(obj(["url": str, "confidence": num])),
            "addresses": arr(obj([
                "street": nullable(str), "city": nullable(str), "region": nullable(str), "postal_code": nullable(str),
                "country": nullable(str), "formatted": nullable(str), "confidence": num,
            ])),
            "social": arr(obj([
                "service": enumStr(["linkedin", "wechat", "line", "whatsapp", "instagram", "facebook", "x", "other"]),
                "handle": str, "confidence": num,
            ])),
            "notes_on_card": nullable(str),
            "evidence": obj([
                "ignored_text": arr(str), "has_person_photo": bool, "has_qr_code": bool,
                "overall_confidence": num, "concerns": arr(str),
            ]),
        ])
    }

    // MARK: Second opinion on one field

    public static let verifySystem = """
    You are the second, independent reader in a business-card pipeline. Another model read the card; one field is \
    uncertain. Look at the image yourself, character by character, and report exactly what is printed for that \
    field. Do not be swayed by the candidates — they may all be wrong. If the card prints several values of this kind \
    (office, mobile and fax numbers; head-office and branch addresses), read the one the field description points to — \
    same label, same position — never a different one. For a phone, include an extension printed with it. \
    Distinguish variant characters exactly (恆/恒, 峯/峰, 着/著). If the field is not printed, value = null. \
    confidence = probability your value is exactly right.
    """

    public static func verifyUser(fieldLabel: String, candidates: [String], ocrHint: [String]) -> String {
        var s = "Field: \(fieldLabel)\nCandidate readings from the first pass: " + candidates.map { "\"\($0)\"" }.joined(separator: ", ")
        if !ocrHint.isEmpty { s += "\nOn-device OCR lines that may be relevant:\n" + ocrHint.map { "- " + $0 }.joined(separator: "\n") }
        s += "\nReturn the exact printed value."
        return s
    }

    public static var verifySchema: [String: Any] {
        obj(["value": nullable(str), "confidence": num, "notes": str])
    }

    // MARK: Grouping resolver (text only, no images)

    public static let groupingSystem = """
    You match the sides of business cards photographed in one batch. Each item is the structured data read from \
    one photo. Some photos are the back of a card whose front is another item; backs often carry no name. Decide, \
    for each item in "unassigned", which person group it belongs to, using company, domain, phone numbers, \
    address, language pairs (e.g. Chinese on one side, English on the other) and capture time. If the evidence is \
    not clear, answer null — a wrong merge corrupts a contact.
    """

    public static var groupingSchema: [String: Any] {
        obj(["assignments": arr(obj(["photo_id": str, "group": nullable(["type": "integer"]), "confidence": num, "reason": str]))])
    }

    // MARK: Voice note → structured note

    public static let voiceNoteSystem = """
    The user dictated a short note about a person they just met (any language, often Chinese/English mixed). \
    Turn it into concise labelled facts for the contact's Notes field. Keep the user's wording for names, \
    places and products; do not add facts that were not said. Use null for anything not mentioned.
    """

    public static var voiceNoteSchema: [String: Any] {
        obj([
            "met_at": nullable(str), "event": nullable(str), "date_mentioned": nullable(str), "industry": nullable(str),
            "appearance": nullable(str), "interests": arr(str), "follow_up": nullable(str), "other": arr(str),
        ])
    }

    public static func jsonString(_ obj: [String: Any], pretty: Bool = false) -> String {
        let data = try! JSONSerialization.data(withJSONObject: obj, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
