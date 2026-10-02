import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP abstraction so the client is testable and works on Linux.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession
    public init(timeout: TimeInterval = 180) {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        session = URLSession(configuration: cfg)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = session.dataTask(with: request) { data, response, error in
                if let error { cont.resume(throwing: error); return }
                guard let http = response as? HTTPURLResponse else { cont.resume(throwing: URLError(.badServerResponse)); return }
                cont.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }
}

public enum LLMError: Error, CustomStringConvertible, Equatable {
    case missingAPIKey
    case unauthorized(String)          // bad key → stop the batch, tell the user once
    case transient(String)             // 429 / 5xx / network → retry later, never "failed"
    case permanent(String)             // 400 etc. → this photo fails, the batch continues
    case refused(String)               // safety classifier declined
    case badOutput(String)

    public var description: String {
        switch self {
        case .missingAPIKey: return "missing API key"
        case .unauthorized(let s): return "unauthorized: \(s)"
        case .transient(let s): return "transient: \(s)"
        case .permanent(let s): return "permanent: \(s)"
        case .refused(let s): return "refused: \(s)"
        case .badOutput(let s): return "bad output: \(s)"
        }
    }

    public var isTransient: Bool { if case .transient = self { return true }; return false }
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0
    public var costUSD = 0.0
    public init() {}

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        var r = TokenUsage()
        r.inputTokens = a.inputTokens + b.inputTokens; r.outputTokens = a.outputTokens + b.outputTokens
        r.cacheReadTokens = a.cacheReadTokens + b.cacheReadTokens; r.cacheWriteTokens = a.cacheWriteTokens + b.cacheWriteTokens
        r.costUSD = a.costUSD + b.costUSD
        return r
    }
}

public struct ModelPricing: Sendable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double
    public var cacheReadPerMTok: Double

    /// First-party API list prices (USD per million tokens).
    public static func forModel(_ id: String) -> ModelPricing {
        switch id {
        case "claude-fable-5-1", "claude-fable-5": return ModelPricing(inputPerMTok: 10, outputPerMTok: 50, cacheReadPerMTok: 0.25)
        case "claude-opus-5-5": return ModelPricing(inputPerMTok: 4, outputPerMTok: 20, cacheReadPerMTok: 0.20)
        case "claude-sonnet-5-5", "claude-sonnet-5": return ModelPricing(inputPerMTok: 2, outputPerMTok: 10, cacheReadPerMTok: 0.20)
        case "claude-haiku-4-5": return ModelPricing(inputPerMTok: 1, outputPerMTok: 5, cacheReadPerMTok: 0.10)
        default: return ModelPricing(inputPerMTok: 5, outputPerMTok: 25, cacheReadPerMTok: 0.5)
        }
    }

    func cost(_ u: TokenUsage) -> Double {
        (Double(u.inputTokens) * inputPerMTok + Double(u.cacheWriteTokens) * inputPerMTok * 1.25
            + Double(u.cacheReadTokens) * cacheReadPerMTok + Double(u.outputTokens) * outputPerMTok) / 1_000_000
    }
}

public struct ImagePayload: Sendable {
    public var data: Data
    public var mediaType: String
    public init(data: Data, mediaType: String = "image/jpeg") { self.data = data; self.mediaType = mediaType }
}

public struct ClaudeConfig: Codable, Sendable {
    public var apiKey: String
    public var baseURL = "https://api.anthropic.com"
    /// Primary reader. Accuracy is the top priority, so the default is the current Opus model.
    public var extractionModel = "claude-opus-5-5"
    public var extractionEffort = "medium"
    /// Second reader for uncertain fields (asked a narrow question about one field). Opus 5.5 is the combination
    /// the benchmark measured; Fable 5.1 is available as a stronger, more independent (and pricier) option.
    public var verifierModel = "claude-opus-5-5"
    public var verifierEffort = "high"
    /// Text-only helpers (grouping resolver, voice notes).
    public var helperModel = "claude-opus-5-5"
    public var maxRetries = 4
    /// Base for exponential backoff between retries (seconds).
    public var retryBaseDelay = 1.0
    /// Server-side refusal fallback (routes a declined request to another model inside the same call).
    public var useRefusalFallback = true

    public init(apiKey: String) { self.apiKey = apiKey }
}

/// Raw-HTTP Messages API client (there is no official Swift SDK).
public final class ClaudeClient: @unchecked Sendable {
    public let config: ClaudeConfig
    let transport: HTTPTransport
    /// Set after the API rejects `output_config.format` once; we then ask for JSON in the prompt instead.
    private var structuredOutputUnsupported = false
    /// Set if the deployment rejects the refusal-fallback beta; we then send requests without it.
    private var fallbackUnsupported = false
    private let lock = NSLock()

    public init(config: ClaudeConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config; self.transport = transport
    }

    public struct Result: Sendable {
        public var json: [String: Any]
        public var rawText: String
        public var usage: TokenUsage
        public var servedBy: String
        public var latency: TimeInterval
    }

    /// One structured request. Retries transient failures with exponential backoff + Retry-After.
    public func structured(model: String, effort: String?, system: String, userText: String, images: [ImagePayload],
                           schema: [String: Any], maxTokens: Int = 8000) async throws -> Result {
        guard !config.apiKey.isEmpty else { throw LLMError.missingAPIKey }
        var attempt = 0
        var lastError: LLMError = .transient("not attempted")
        while attempt <= config.maxRetries {
            do {
                return try await once(model: model, effort: effort, system: system, userText: userText, images: images,
                                      schema: schema, maxTokens: maxTokens)
            } catch let e as LLMError {
                lastError = e
                guard e.isTransient else { throw e }
            } catch let e as URLError {
                lastError = .transient("network: \(e.code.rawValue)")
            } catch {
                throw LLMError.badOutput(String(describing: error))
            }
            attempt += 1
            if attempt <= config.maxRetries {
                let delay = min(config.retryBaseDelay * pow(2.0, Double(attempt)) + Double.random(in: 0...config.retryBaseDelay), 30)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError
    }

    private func once(model: String, effort: String?, system: String, userText: String, images: [ImagePayload],
                      schema: [String: Any], maxTokens: Int) async throws -> Result {
        let started = Date()
        let useStructured = lock.locked { !structuredOutputUnsupported }
        var content: [[String: Any]] = images.map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.data.base64EncodedString()]]
        }
        var text = userText
        if !useStructured {
            text += "\n\nRespond with ONLY a JSON object (no prose, no code fence) that validates against this JSON schema:\n"
                + Prompts.jsonString(schema)
        }
        content.append(["type": "text", "text": text])
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": content]],
        ]
        var outputConfig: [String: Any] = [:]
        if let effort { outputConfig["effort"] = effort }
        if useStructured { outputConfig["format"] = ["type": "json_schema", "schema": schema] }
        if !outputConfig.isEmpty { body["output_config"] = outputConfig }
        var betas: [String] = []
        if config.useRefusalFallback && !lock.locked({ fallbackUnsupported }) {
            body["fallbacks"] = "default"
            betas.append("server-side-fallback-2026-07-01")
        }

        var req = URLRequest(url: URL(string: config.baseURL + "/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty { req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await transport.send(req)
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        switch http.statusCode {
        case 200: break
        case 401, 403: throw LLMError.unauthorized(bodyText.prefix(300).description)
        case 408, 409, 429, 500...599: throw LLMError.transient("HTTP \(http.statusCode): \(bodyText.prefix(200))")
        case 400:
            let lower = bodyText.lowercased()
            if useStructured && (lower.contains("output_config") || lower.contains("json_schema") || lower.contains("output format")) {
                lock.locked { structuredOutputUnsupported = true }
                throw LLMError.transient("structured output rejected, retrying with prompt-based JSON")
            }
            if body["fallbacks"] != nil && lower.contains("fallback") {
                // A deployment that does not know the fallback beta: retry without it.
                lock.locked { fallbackUnsupported = true }
                throw LLMError.transient("fallback parameter rejected, retrying without it")
            }
            throw LLMError.permanent("HTTP 400: \(bodyText.prefix(300))")
        default: throw LLMError.permanent("HTTP \(http.statusCode): \(bodyText.prefix(300))")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LLMError.badOutput("not json") }
        let stop = obj["stop_reason"] as? String
        if stop == "refusal" { throw LLMError.refused((obj["stop_details"] as? [String: Any])?.description ?? "") }
        if stop == "max_tokens" { throw LLMError.transient("max_tokens reached") }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        let texts = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }
        guard let raw = texts.last else { throw LLMError.badOutput("no text block") }
        guard let json = Self.parseJSONObject(raw) else { throw LLMError.badOutput("unparseable JSON: \(raw.prefix(200))") }
        var usage = TokenUsage()
        if let u = obj["usage"] as? [String: Any] {
            usage.inputTokens = u["input_tokens"] as? Int ?? 0
            usage.outputTokens = u["output_tokens"] as? Int ?? 0
            usage.cacheReadTokens = u["cache_read_input_tokens"] as? Int ?? 0
            usage.cacheWriteTokens = u["cache_creation_input_tokens"] as? Int ?? 0
        }
        let served = obj["model"] as? String ?? model
        usage.costUSD = ModelPricing.forModel(served).cost(usage)
        return Result(json: json, rawText: raw, usage: usage, servedBy: served, latency: Date().timeIntervalSince(started))
    }

    /// Accepts a bare object or one wrapped in prose / code fences.
    static func parseJSONObject(_ s: String) -> [String: Any]? {
        if let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end else { return nil }
        let sub = String(s[start...end])
        guard let d = sub.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}

extension NSLock {
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
