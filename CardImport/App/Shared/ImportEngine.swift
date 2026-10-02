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
        // On-device only: free and private, but expect more review items.
        return BatchProcessor(store: store, images: images, ocr: ocr, extractor: HeuristicExtractor(defaultRegion: config.defaultRegion),
                              verifier: nil, resolver: nil, index: contacts, writer: contacts, config: config)
    }

    /// Imports raw image data (from PhotosPicker, the share sheet or a Shortcut) and processes the batch.
    func importImages(_ datas: [Data], source: String) async {
        guard !datas.isEmpty else { return }
        if AppSettings.useCloudAI && (KeychainStore.load() ?? "").isEmpty { stage = .needsAPIKey; return }
        if !stopBeforeWriting {
            let granted = await contacts.requestAccess()
            if !granted { stage = .needsContactsAccess; return }
        }
        stage = .preparing(done: 0, total: datas.count)
        var photos: [PhotoRecord] = []
        // Prepare sequentially to keep memory low (share extensions have a small memory budget).
        for (i, data) in datas.enumerated() {
            let prepared: ImagePreparer.Prepared? = await Task.detached(priority: .userInitiated) { ImagePreparer.prepare(data) }.value
            if let prepared {
                let id = UUID().uuidString
                do {
                    try images.save(prepared.jpeg, id: id)
                    photos.append(PhotoRecord(id: id, index: i, captureDate: prepared.captureDate, visual: prepared.visual))
                } catch { lastError = error.localizedDescription }
            }
            stage = .preparing(done: i + 1, total: datas.count)
        }
        let batch = BatchState(source: source, photos: photos)
        try? await store.save(batch)
        await run(batch)
    }

    func run(_ batch: BatchState) async {
        guard let processor = makeProcessor() else { stage = .needsAPIKey; return }
        state = batch
        stage = .processing(BatchProgressView(phase: "recognizing", recognized: 0, total: batch.photos.count, peopleDone: 0, peopleTotal: 0))
        await processor.onProgress { [weak self] p in
            Task { @MainActor in
                self?.stage = .processing(BatchProgressView(phase: p.phase.rawValue, recognized: p.recognized, total: p.totalPhotos,
                                                            peopleDone: p.peopleDone, peopleTotal: p.peopleTotal))
            }
        }
        let token = BackgroundWork.begin(title: "名片匯入", total: batch.photos.count)
        let result = await processor.run(batch)
        BackgroundWork.end(token)
        state = result
        stage = .finished
    }

    /// Resumes batches interrupted by a crash, a kill, lost network or a share extension without Contacts access.
    func resumeUnfinished() async {
        guard case .idle = stage else { return }
        let unfinished = await store.unfinished()
        guard let next = unfinished.first else { return }
        await run(next)
    }

    func answer(_ item: ReviewItem, with value: String?) async {
        guard let s = state, let processor = makeProcessor() else { return }
        state = await processor.answer(item.id, with: value, in: s)
    }

    func retryFailed() async {
        guard let s = state, let processor = makeProcessor(), let retry = await processor.retryBatch(forFailedPhotosOf: s) else { return }
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
        let id = UIApplication.shared.beginBackgroundTask(withName: title) {}
        return Token(id: id)
        #else
        return Token(id: nil)
        #endif
    }

    @MainActor
    static func end(_ t: Token) {
        #if !APP_EXTENSION
        if let id = t.id, id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        #endif
    }
}
