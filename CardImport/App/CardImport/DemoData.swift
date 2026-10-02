import Foundation
import CardCore

/// `-demo completion|review|home` launch argument: shows a screen with sample data (screenshots, UI review).
/// Never touches the address book.
@MainActor
enum DemoData {
    static func requestedScreen() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func apply(_ screen: String, to engine: ImportEngine) {
        AppSettings.onboardingDone = true
        guard screen != "home" else { return }
        engine.state = sampleState()
        engine.stage = .finished
    }

    static func sampleState() -> BatchState {
        var s = BatchState(source: "demo", photos: (0..<20).map { PhotoRecord(id: "demo-\($0)", index: $0) })
        for i in s.photos.indices { s.photos[i].status = .recognized }
        s.phase = .done
        s.people = (0..<15).map { i in
            var p = PersonRecord(id: "p-\(i)", photoIDs: ["demo-\(i)"])
            p.status = i == 7 ? .needsReview : .created
            var d = ContactDraft(id: p.id, photoIDs: p.photoIDs)
            d.givenName = DraftValue(value: ["John", "Mary", "David", "Olivia", "Derek"][i % 5], confidence: 0.99)
            d.familyName = DraftValue(value: ["Chen", "Lee", "Wang", "Chen", "Lau"][i % 5], confidence: 0.99)
            p.draft = d; p.fullDraft = d
            return p
        }
        s.review = [
            ReviewItem(id: "p-7#job_title", personID: "p-7", kind: .field, field: "job_title",
                       question: "職稱 Job title：哪一個正確？", candidates: ["Sales Manager", "Sales Director"], photoIDs: [], blocking: false),
        ]
        s.processingSeconds = 48
        return s
    }
}
