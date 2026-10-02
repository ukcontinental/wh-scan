import SwiftUI
import AppIntents

/// Entry points that can start an import: NFC (Shortcuts automation → App Intent), URL scheme, share sheet.
@MainActor
final class ImportRouter: ObservableObject {
    static let shared = ImportRouter()
    @Published var showPicker = false
    @Published var pendingImages: [Data]? = nil
    @Published var pendingSource = "app"

    func requestPicker(source: String) {
        pendingSource = source
        showPicker = true
    }

    func enqueue(_ images: [Data], source: String) {
        pendingSource = source
        pendingImages = images
    }
}

@main
struct CardImportApp: App {
    @StateObject private var engine = ImportEngine()
    @StateObject private var router = ImportRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(router)
                .onOpenURL { url in
                    // cardimport://import — for NFC tags that carry a URL record instead of a Shortcuts automation.
                    if url.host == "import" { router.requestPicker(source: "url") }
                }
                .task { await engine.resumeUnfinished() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await engine.resumeUnfinished() } }
                }
        }
    }
}
