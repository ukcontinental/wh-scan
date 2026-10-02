import Foundation
import CardCore

// Command-line driver used by the benchmark harness (runs the exact same pipeline code as the app,
// with tesseract standing in for Apple Vision OCR and an in-memory address book standing in for Contacts).

struct Args {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var command = ""
    init(_ argv: [String]) {
        var it = argv.dropFirst().makeIterator()
        command = it.next() ?? ""
        while let a = it.next() {
            guard a.hasPrefix("--") else { continue }
            let key = String(a.dropFirst(2))
            if let eq = key.firstIndex(of: "=") { values[String(key[..<eq])] = String(key[key.index(after: eq)...]); continue }
            if ["verify", "no-resolver", "help"].contains(key) { flags.insert(key); continue }
            values[key] = it.next() ?? ""
        }
    }
    func get(_ k: String, _ d: String = "") -> String { values[k] ?? d }
}

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data(("error: " + m + "\n").utf8)); exit(2) }
func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }

struct PhotoInput: Codable {
    var id: String
    var file: String
    var captureTime: Double?
    var colorHistogram: [Double]?
    var aspectRatio: Double?
}

struct FileImageStore: ImageStore {
    let paths: [String: String]
    func load(_ photoID: String) async throws -> ImagePayload {
        guard let p = paths[photoID] else { throw LLMError.permanent("unknown photo \(photoID)") }
        let data = try Data(contentsOf: URL(fileURLWithPath: p))
        return ImagePayload(data: data, mediaType: p.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg")
    }
    func delete(_ photoID: String) async {}   // never delete benchmark inputs
}

/// tesseract as the stand-in for Apple Vision (Vision is not available on Linux). Results are cached.
struct TesseractOCR: OCRProvider {
    let cacheDir: URL?
    let pathsByHash: [Int: String]

    func recognize(_ image: ImagePayload) async throws -> OCRResult {
        let key = image.data.hashValue
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-\(UUID().uuidString).jpg")
        try image.data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let cacheDir {
            let cacheFile = cacheDir.appendingPathComponent(sha(image.data) + ".json")
            if let d = try? Data(contentsOf: cacheFile), let r = try? JSONDecoder().decode(OCRResult.self, from: d) { return r }
            let r = try run(tmp)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? JSONEncoder().encode(r).write(to: cacheFile)
            _ = key
            return r
        }
        return try run(tmp)
    }

    func sha(_ d: Data) -> String {
        // FNV-1a 64 (cache key only).
        var h: UInt64 = 0xcbf29ce484222325
        for b in d { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    func run(_ file: URL) throws -> OCRResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tesseract")
        p.arguments = [file.path, "stdout", "-l", "eng+chi_tra+chi_sim", "--psm", "11", "tsv"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        // level page_num block_num par_num line_num word_num left top width height conf text
        struct W { var text: String; var conf: Double; var l: Double; var t: Double; var w: Double; var h: Double }
        var lines: [String: [W]] = [:]
        var order: [String] = []
        var pageW = 1.0, pageH = 1.0
        for row in text.split(separator: "\n").dropFirst() {
            let c = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 12 else { continue }
            if c[0] == "1" { pageW = Double(c[8]) ?? 1; pageH = Double(c[9]) ?? 1 }
            guard c[0] == "5", let conf = Double(c[10]), conf >= 0 else { continue }
            let word = c[11].trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            let k = "\(c[2])-\(c[3])-\(c[4])"
            if lines[k] == nil { order.append(k) }
            lines[k, default: []].append(W(text: word, conf: conf / 100, l: Double(c[6])!, t: Double(c[7])!, w: Double(c[8])!, h: Double(c[9])!))
        }
        let result: [OCRLine] = order.compactMap { k in
            guard let ws = lines[k], !ws.isEmpty else { return nil }
            // CJK words are joined without spaces.
            var s = ""
            for w in ws {
                if let last = s.last, TextNorm.containsCJK(String(last)) && TextNorm.containsCJK(w.text) { s += w.text }
                else { s += (s.isEmpty ? "" : " ") + w.text }
            }
            let l = ws.map(\.l).min()!, t = ws.map(\.t).min()!
            let r = ws.map { $0.l + $0.w }.max()!, b = ws.map { $0.t + $0.h }.max()!
            return OCRLine(text: s, confidence: ws.map(\.conf).reduce(0, +) / Double(ws.count),
                           box: [l / pageW, t / pageH, (r - l) / pageW, (b - t) / pageH])
        }
        return OCRResult(engine: "tesseract", lines: result)
    }
}

struct ReplayExtractor: CardExtractor {
    let dir: URL
    let idByHash: [String: String]
    func extract(image: ImagePayload, ocr: OCRResult?) async throws -> ExtractionOutput {
        guard let id = idByHash[TesseractOCR(cacheDir: nil, pathsByHash: [:]).sha(image.data)] else { throw LLMError.permanent("unknown image") }
        let f = dir.appendingPathComponent(id + ".json")
        guard let d = try? Data(contentsOf: f) else { throw LLMError.permanent("no replay file for \(id)") }
        do {
            return ExtractionOutput(card: try CardJSON.llmDecoder().decode(ExtractedCard.self, from: d), model: "replay")
        } catch { throw LLMError.badOutput("replay \(id): \(error)") }
    }
}

/// Saves every Claude extraction so runs can be replayed / re-scored without new API calls.
struct SavingExtractor: CardExtractor {
    let inner: CardExtractor
    let dir: URL
    let idByHash: [String: String]
    func extract(image: ImagePayload, ocr: OCRResult?) async throws -> ExtractionOutput {
        let out = try await inner.extract(image: image, ocr: ocr)
        if let id = idByHash[TesseractOCR(cacheDir: nil, pathsByHash: [:]).sha(image.data)] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? CardJSON.llmEncoder(pretty: true).encode(out.card).write(to: dir.appendingPathComponent(id + ".json"))
        }
        return out
    }
}

struct RunOutput: Codable {
    var config: [String: String]
    var summary: BatchSummary
    var phase: BatchPhase
    var photos: [PhotoRecord]
    var people: [PersonRecord]
    var review: [ReviewItem]
    var grouping: GroupingResult?
    var addressBook: [InMemoryAddressBook.Stored]
    var wallSeconds: Double
}

func run(_ a: Args) async {
    let photosFile = a.get("photos")
    guard !photosFile.isEmpty, let pd = try? Data(contentsOf: URL(fileURLWithPath: photosFile)),
          let inputs = try? JSONDecoder().decode([PhotoInput].self, from: pd) else { fail("--photos <photos.json> required") }
    let base = URL(fileURLWithPath: photosFile).deletingLastPathComponent()
    func abs(_ f: String) -> String { f.hasPrefix("/") ? f : base.appendingPathComponent(f).path }
    let paths = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, abs($0.file)) })
    var idByHash: [String: String] = [:]
    for i in inputs { if let d = try? Data(contentsOf: URL(fileURLWithPath: abs(i.file))) { idByHash[TesseractOCR(cacheDir: nil, pathsByHash: [:]).sha(d)] = i.id } }

    let ocrMode = a.get("ocr", "tesseract")
    let ocr: OCRProvider? = ocrMode == "none" ? nil : TesseractOCR(cacheDir: URL(fileURLWithPath: a.get("ocr-cache", "/tmp/cardcore-ocr-cache")), pathsByHash: [:])
    let region = a.get("region", "CA")
    let extractorMode = a.get("extractor", "heuristic")
    var extractor: CardExtractor
    var verifier: FieldVerifier? = nil
    var resolver: GroupingResolver? = nil
    if extractorMode == "heuristic" {
        extractor = HeuristicExtractor(defaultRegion: region)
    } else if extractorMode.hasPrefix("replay:") {
        extractor = ReplayExtractor(dir: URL(fileURLWithPath: String(extractorMode.dropFirst(7))), idByHash: idByHash)
    } else if extractorMode == "claude" {
        let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        if key.isEmpty { fail("ANTHROPIC_API_KEY is not set") }
        var cfg = ClaudeConfig(apiKey: key)
        if let m = a.values["model"] { cfg.extractionModel = m }
        if let e = a.values["effort"] { cfg.extractionEffort = e }
        if let m = a.values["verifier-model"] { cfg.verifierModel = m }
        let client = ClaudeClient(config: cfg)
        extractor = ClaudeExtractor(client: client)
        if let save = a.values["save-extractions"] { extractor = SavingExtractor(inner: extractor, dir: URL(fileURLWithPath: save), idByHash: idByHash) }
        if a.flags.contains("verify") { verifier = ClaudeFieldVerifier(client: client) }
        if !a.flags.contains("no-resolver") { resolver = ClaudeGroupingResolver(client: client) }
    } else { fail("unknown --extractor \(extractorMode)") }

    var existing: [ExistingContact] = []
    if let ef = a.values["existing"], let d = try? Data(contentsOf: URL(fileURLWithPath: ef)) {
        existing = (try? JSONDecoder().decode([ExistingContact].self, from: d)) ?? []
    }
    let book = InMemoryAddressBook(existing: existing)
    var config = BatchConfig()
    config.defaultRegion = region
    config.deleteImagesWhenDone = false
    config.maxConcurrentRecognitions = Int(a.get("concurrency", "4")) ?? 4
    if let t = a.values["auto-critical"], let v = Double(t) { config.policy.autoAcceptCritical = v }
    if let t = a.values["auto-other"], let v = Double(t) { config.policy.autoAcceptOther = v }

    let stateDir = URL(fileURLWithPath: a.get("state-dir", FileManager.default.temporaryDirectory.appendingPathComponent("cardcore-state").path))
    let processor = BatchProcessor(store: BatchStore(directory: stateDir), images: FileImageStore(paths: paths), ocr: ocr,
                                   extractor: extractor, verifier: verifier, resolver: resolver, index: book, writer: book, config: config)
    await processor.onProgress { p in log("[\(p.phase.rawValue)] photos \(p.recognized)/\(p.totalPhotos) people \(p.peopleDone)/\(p.peopleTotal)") }
    let photos = inputs.enumerated().map { (i, p) -> PhotoRecord in
        PhotoRecord(id: p.id, index: i, captureDate: p.captureTime.map { Date(timeIntervalSince1970: $0) },
                    visual: p.colorHistogram.map { VisualSignature(colorHistogram: $0, aspectRatio: p.aspectRatio) })
    }
    let t0 = Date()
    let state = await processor.run(BatchState(source: "cli", photos: photos))
    let wall = Date().timeIntervalSince(t0)
    let out = RunOutput(config: ["extractor": extractorMode, "ocr": ocrMode, "verify": "\(verifier != nil)", "region": region],
                        summary: state.summary, phase: state.phase, photos: state.photos, people: state.people, review: state.review,
                        grouping: state.grouping, addressBook: await book.contacts, wallSeconds: wall)
    let data = try! CardJSON.encoder(pretty: true).encode(out)
    let outFile = a.get("out", "run.json")
    try! data.write(to: URL(fileURLWithPath: outFile))
    let s = state.summary
    log("done: photos=\(s.photos) people=\(s.peopleDetected) created=\(s.created) updated=\(s.updated) existing=\(s.alreadyExisted) review=\(s.openReviewItems) failed=\(s.failedPhotos) cost=$\(String(format: "%.3f", s.costUSD)) wall=\(String(format: "%.1f", wall))s → \(outFile)")
}

let args = Args(CommandLine.arguments)
switch args.command {
case "run":
    let sem = DispatchSemaphore(value: 0)
    Task { await run(args); sem.signal() }
    sem.wait()
case "schema":
    print(Prompts.jsonString(Prompts.extractionSchema, pretty: true))
case "prompt":
    print(Prompts.extractionSystem)
case "ocr":
    // Debug: cardcore-cli ocr <image>
    let file = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
    let r = try! TesseractOCR(cacheDir: nil, pathsByHash: [:]).run(URL(fileURLWithPath: file))
    for l in r.lines { print(String(format: "%.2f", l.confidence), l.text) }
default:
    print("""
    usage:
      cardcore-cli run --photos photos.json [--extractor heuristic|claude|replay:DIR] [--ocr tesseract|none]
                       [--ocr-cache DIR] [--existing contacts.json] [--verify] [--save-extractions DIR] [--out run.json]
      cardcore-cli schema | prompt | ocr <image>
    """)
}
