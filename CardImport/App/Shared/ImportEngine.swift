import Foundation
import UIKit
import CardCore

/// Builds the pipeline from settings and runs batches. Shared by the app and the share extension.
@MainActor
final class ImportEngine: ObservableObject {
    enum Stage: Equatable {
        case idle
        case preparing(done: Int, total: Int)
        case processing(BatchProgressView)
        case finished
        case needsAPIKey
        case needsContactsAccess
    }

    struct BatchProgressView: Equatable {
        var phase: String
        var recognized: Int
        var total: Int
        var peopleDone: Int
        var peopleTotal: Int
    }

    @Published var stage: Stage = .idle
    @Published var state: BatchState?
    @Published var lastError: String?

    let images = TempImageStore()
    let contacts = ContactsService()
    let store = BatchStore(directory: AppGroup.batchesDir)
    /// Share extension: no Contacts access yet → recognise now, write later in the app.
    var stopBeforeWriting = false
    /// Set synchronously before any suspension point so two triggers (launch + foreground, NFC + resume)
    /// can never run the same batch twice at once.
    private var busy = false
    /// Imports requested while another batch is running (e.g. NFC tapped again) wait here instead of being dropped.
    private var queued: [(loaders: [@Sendable () async -> Data?], source: String)] = []
    /// Progress callbacks hop to the main actor asynchronously; late ones from a finished run are ignored.
    private var activeRun: UUID?

    func makeProcessor() -> BatchProcessor? {
        var config = BatchConfig()
        config.defaultRegion = AppSettings.defaultRegion
        config.stopBeforeWriting = stopBeforeWriting
        let ocr = VisionOCR()
        if AppSettings.useCloudAI {
            guard let key = KeychainStore.load(), !key.isEmpty else { return nil }
            var cfg = ClaudeConfig(apiKey: key)
            cfg.extractionModel = AppSettings.extractionModel
            cfg.verifierModel = AppSettings.verifierModel
            let client = ClaudeClient(config: cfg)
            return BatchProcessor(store: store, images: images, ocr: ocr, extractor: ClaudeExtractor(client: client),
                                  verifier: AppSettings.secondOpinion ? ClaudeFieldVerifier(client: client) : nil,
                                  resolver: ClaudeGroupingResolver(client: client), index: contacts, writer: contacts, config: config)
        }
        // On-device only (user turned AI off for privacy). Rule-based field classification is not reliable
        // (benchmark: ~50% of contacts would get a wrong value at normal thresholds), so nothing is written
        // unasked unless it is near-certain: correctness over automation.
        config.policy.autoAcceptCritical = 0.98
        config.policy.autoAcceptOther = 0.97
        return BatchProcessor(store: store, images: images, ocr: ocr, extractor: HeuristicExtractor(defaultRegion: config.defaultRegion),
                              verifier: nil, resolver: nil, index: contacts, writer: contacts, config: config)
    }

    /// Imports raw image data (from PhotosPicker, the share sheet or a Shortcut) and processes the batch.
    func importImages(_ datas: [Data], source: String) async {
        await importImages(loaders: datas.map { d in { d } }, source: source)
    }

    /// Loads, prepares and stores one photo at a time so the original images are never all in memory
    /// (the share extension has a small memory budget).
    func importImages(loaders: [@Sendable () async -> Data?], source: String) async {
        guard !loaders.isEmpty else { return }
        queued.append((loaders, source))
        guard !busy else { return }
        busy = true
        await drainQueue()
        busy = false
    }

    private func drainQueue() async {
        while !queued.isEmpty {
            let next = queued.removeFirst()
            await importNow(next.loaders, source: next.source)
        }
    }

    private func importNow(_ loaders: [@Sendable () async -> Data?], source: String) async {
        if AppSettings.useCloudAI && (KeychainStore.load() ?? "").isEmpty { stage = .needsAPIKey; return }
        if !stopBeforeWriting {
            let granted = await contacts.requestAccess()
            if !granted { stage = .needsContactsAccess; return }
        }
        stage = .preparing(done: 0, total: loaders.count)
        var photos: [PhotoRecord] = []
        for (i, load) in loaders.enumerated() {
            guard let data = await load() else { stage = .preparing(done: i + 1, total: loaders.count); continue }
            let prepared: ImagePreparer.Prepared? = await Task.detached(priority: .userInitiated) { ImagePreparer.prepare(data) }.value
            if let prepared {
                let id = UUID().uuidString
                do {
                    try images.save(prepared.jpeg, id: id)
                    photos.append(PhotoRecord(id: id, index: i, captureDate: prepared.captureDate, visual: prepared.visual))
                } catch { lastError = error.localizedDescription }
            }
            stage = .preparing(done: i + 1, total: loaders.count)
        }
        let batch = BatchState(source: source, photos: photos)
        try? await store.save(batch)
        await runLocked(batch)
    }

    func run(_ batch: BatchState) async {
        guard !busy else { return }
        busy = true
        await runLocked(batch)
        await drainQueue()
        busy = false
    }

    private func runLocked(_ batch: BatchState) async {
        guard let processor = makeProcessor() else { stage = .needsAPIKey; return }
        state = batch
        let runID = UUID()
        activeRun = runID
        stage = .processing(BatchProgressView(phase: "recognizing", recognized: 0, total: batch.photos.count, peopleDone: 0, peopleTotal: 0))
        await processor.onProgress { [weak self] p in
            Task { @MainActor in
                guard let self, self.activeRun == runID else { return }
                self.stage = .processing(BatchProgressView(phase: p.phase.rawValue, recognized: p.recognized, total: p.totalPhotos,
                                                            peopleDone: p.peopleDone, peopleTotal: p.peopleTotal))
                BackgroundWork.progress(done: p.recognized + p.peopleDone, total: p.totalPhotos + max(p.peopleTotal, 1),
                                        subtitle: p.peopleTotal > 0 ? "\(p.peopleDone) / \(p.peopleTotal) 位" : "\(p.recognized) / \(p.totalPhotos) 張")
            }
        }
        let token = BackgroundWork.begin(title: "名片匯入", total: batch.photos.count)
        let result = await processor.run(batch)
        activeRun = nil
        BackgroundWork.end(token, success: result.phase == .done)
        state = result
        stage = .finished
    }

    /// Resumes batches interrupted by a crash, a kill, lost network or a share extension without Contacts access.
    func resumeUnfinished() async {
        guard case .idle = stage, !busy else { return }
        busy = true
        if let next = await store.unfinished().first { await runLocked(next) }
        await drainQueue()
        busy = false
    }

    /// Recent batches for the processing log (newest first).
    func recentBatches(limit: Int = 20) async -> [BatchState] {
        Array(await store.all().prefix(limit))
    }

    func answer(_ item: ReviewItem, with value: String?) async {
        guard let s = state, let processor = makeProcessor() else { return }
        state = await processor.answer(item.id, with: value, in: s)
    }

    func retryFailed() async {
        guard !busy, let s = state, let processor = makeProcessor(), let retry = await processor.retryBatch(forFailedPhotosOf: s) else { return }
        try? await store.save(retry)
        await run(retry)
    }

    func reset() {
        stage = .idle
        state = nil
    }
}

/// Keeps the batch running for a while after the user leaves the app.
enum BackgroundWork {
    struct Token { var id: UIBackgroundTaskIdentifier? }

    @MainActor
    static func begin(title: String, total: Int) -> Token {
        #if !APP_EXTENSION
        ContinuedProcessing.shared.begin(title: title, total: total)
        let id = UIApplication.shared.beginBackgroundTask(withName: title) {}
        return Token(id: id)
        #else
        return Token(id: nil)
        #endif
    }

    @MainActor
    static func progress(done: Int, total: Int, subtitle: String) {
        #if !APP_EXTENSION
        ContinuedProcessing.shared.update(done: done, total: total, subtitle: subtitle)
        #endif
    }

    @MainActor
    static func end(_ t: Token, success: Bool) {
        #if !APP_EXTENSION
        ContinuedProcessing.shared.end(success: success)
        if let id = t.id, id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        #endif
    }
}
