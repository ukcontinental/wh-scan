import XCTest
@testable import CardCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MockTransport: HTTPTransport, @unchecked Sendable {
    var responses: [(Int, String)]
    var requests: [[String: Any]] = []
    var headers: [[String: String]] = []
    let lock = NSLock()
    init(_ r: [(Int, String)]) { responses = r }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        requests.append((try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:])
        headers.append(Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }))
        let (code, body) = responses.isEmpty ? (500, "{}") : responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

final class ClaudeClientTests: XCTestCase {
    static func okBody(_ json: String) -> String {
        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return """
        {"model":"claude-opus-5-5","stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"\(escaped)"}],
         "usage":{"input_tokens":2100,"output_tokens":650,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
        """
    }

    static let cardJSON = """
    {"schema_version":1,"card_side":"front","is_business_card":true,"language_hint":["en","zh-Hant"],
     "name":{"given":{"value":"David","confidence":0.98,"alternatives":[],"source_text":"David Wang"},
             "family":{"value":"Wang","confidence":0.98,"alternatives":[],"source_text":"David Wang"},
             "cjk_full":{"value":"王大明","confidence":0.97,"alternatives":[],"source_text":"王大明"},"prefix":null,"suffix":null},
     "company":{"value":"ABC Foods Ltd.","confidence":0.97,"alternatives":[],"source_text":"ABC Foods Ltd."},
     "company_cjk":null,"job_title":{"value":"Sales Manager","confidence":0.95,"alternatives":[],"source_text":"Sales Manager"},
     "job_title_cjk":null,"department":null,
     "phones":[{"kind":"mobile","number":"416-555-0137","extension":null,"country_hint":"CA","confidence":0.98,"alternatives":[],"source_text":"M 416-555-0137"}],
     "emails":[{"address":"david@abcfoods.com","confidence":0.98,"alternatives":[],"source_text":"david@abcfoods.com"}],
     "websites":[{"url":"www.abcfoods.com","confidence":0.97}],"addresses":[],"social":[],"notes_on_card":null,
     "evidence":{"ignored_text":["Quality Since 1985"],"has_person_photo":false,"has_qr_code":true,"overall_confidence":0.95,"concerns":[]}}
    """

    func client(_ t: MockTransport) -> ClaudeClient {
        var cfg = ClaudeConfig(apiKey: "test-key")
        cfg.retryBaseDelay = 0.001
        cfg.maxRetries = 3
        return ClaudeClient(config: cfg, transport: t)
    }

    func testExtractionParsesAndPricesUsage() async throws {
        let t = MockTransport([(200, Self.okBody(Self.cardJSON))])
        let out = try await ClaudeExtractor(client: client(t)).extract(image: ImagePayload(data: Data([1, 2, 3])), ocr: nil)
        XCTAssertEqual(out.card.name.cjkFull?.value, "王大明")
        XCTAssertEqual(out.card.phones.first?.countryHint, "CA")
        XCTAssertEqual(out.card.evidence.ignoredText, ["Quality Since 1985"])
        XCTAssertEqual(out.usage.inputTokens, 2100)
        XCTAssertEqual(out.usage.costUSD, (2100 * 4 + 650 * 20) / 1_000_000, accuracy: 1e-9)
        // Request shape: structured output, effort, fallback beta, image block first.
        let body = t.requests[0]
        let oc = body["output_config"] as? [String: Any]
        XCTAssertEqual((oc?["format"] as? [String: Any])?["type"] as? String, "json_schema")
        XCTAssertEqual(oc?["effort"] as? String, "medium")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual(t.headers[0]["anthropic-beta"], "server-side-fallback-2026-07-01")
        let content = (body["messages"] as? [[String: Any]])?[0]["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "image")
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["temperature"])
    }

    func testRetriesOn429ThenSucceeds() async throws {
        let t = MockTransport([(429, "{}"), (529, "{}"), (200, Self.okBody(Self.cardJSON))])
        let out = try await ClaudeExtractor(client: client(t)).extract(image: ImagePayload(data: Data([1])), ocr: nil)
        XCTAssertEqual(out.card.name.given?.value, "David")
        XCTAssertEqual(t.requests.count, 3)
    }

    func testStructuredOutputRejectedFallsBackToPromptJSON() async throws {
        let t = MockTransport([(400, #"{"error":{"message":"output_config.format: unsupported schema feature"}}"#),
                               (200, Self.okBody("Here you go:\n" + Self.cardJSON))])
        let out = try await ClaudeExtractor(client: client(t)).extract(image: ImagePayload(data: Data([1])), ocr: nil)
        XCTAssertEqual(out.card.company?.value, "ABC Foods Ltd.")
        let second = t.requests[1]
        XCTAssertNil((second["output_config"] as? [String: Any])?["format"])
    }

    func testUnauthorizedIsNotRetried() async {
        let t = MockTransport([(401, #"{"error":{"message":"invalid x-api-key"}}"#)])
        do {
            _ = try await ClaudeExtractor(client: client(t)).extract(image: ImagePayload(data: Data([1])), ocr: nil)
            XCTFail("expected error")
        } catch let e as LLMError {
            if case .unauthorized = e {} else { XCTFail("\(e)") }
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(t.requests.count, 1)
    }

    func testRefusalSurfaces() async {
        let t = MockTransport([(200, #"{"model":"x","stop_reason":"refusal","stop_details":{"category":"other"},"content":[],"usage":{}}"#)])
        do {
            _ = try await ClaudeExtractor(client: client(t)).extract(image: ImagePayload(data: Data([1])), ocr: nil)
            XCTFail("expected refusal")
        } catch let e as LLMError {
            if case .refused = e {} else { XCTFail("\(e)") }
        } catch { XCTFail("\(error)") }
    }

    func testSchemaIsStrictAndComplete() throws {
        let schema = Prompts.extractionSchema
        func check(_ o: Any, path: String) {
            guard let d = o as? [String: Any] else { return }
            if d["type"] as? String == "object" {
                XCTAssertEqual(d["additionalProperties"] as? Bool, false, path)
                let props = (d["properties"] as? [String: Any]) ?? [:]
                XCTAssertEqual(Set((d["required"] as? [String]) ?? []), Set(props.keys), path)
                for (k, v) in props { check(v, path: path + "." + k) }
            }
            if let items = d["items"] { check(items, path: path + "[]") }
            if let any = d["anyOf"] as? [Any] { any.forEach { check($0, path: path + "|") } }
            XCTAssertNil(d["minimum"], path); XCTAssertNil(d["maximum"], path)
        }
        check(schema, path: "$")
        // The model's own JSON round-trips through the published schema shape.
        let card = try CardJSON.llmDecoder().decode(ExtractedCard.self, from: Data(Self.cardJSON.utf8))
        let re = try CardJSON.llmDecoder().decode(ExtractedCard.self, from: CardJSON.llmEncoder().encode(card))
        XCTAssertEqual(card, re)
    }
}
