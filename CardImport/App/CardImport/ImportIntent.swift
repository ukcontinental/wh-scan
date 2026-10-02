import AppIntents
import UniformTypeIdentifiers

/// "匯入名片" — used by the NFC personal automation (Shortcuts → Automation → NFC → Run Immediately)
/// and by Siri / Spotlight / the Action button. With no photos it opens the multi-select picker directly;
/// with photos (e.g. a Shortcut that received images from the share sheet) it imports them at once.
struct ImportBusinessCardsIntent: AppIntent {
    static var title: LocalizedStringResource = "匯入名片"
    static var description = IntentDescription("選擇名片照片，自動建立 iPhone 聯絡人。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "照片", supportedContentTypes: [.image])
    var photos: [IntentFile]?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if let photos, !photos.isEmpty {
            ImportRouter.shared.enqueue(photos.map(\.data), source: "shortcut")
        } else {
            ImportRouter.shared.requestPicker(source: "nfc")
        }
        return .result()
    }
}

struct CardImportShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ImportBusinessCardsIntent(),
                    phrases: ["用\(.applicationName)匯入名片", "Import business cards with \(.applicationName)"],
                    shortTitle: "匯入名片",
                    systemImageName: "person.crop.rectangle.stack")
    }
}
