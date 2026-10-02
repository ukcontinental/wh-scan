import Foundation

/// Paths and settings shared by the app and the share extension through the App Group container.
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.example.cardimport"
    }

    static var container: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) { return url }
        // Fallback when the App Group is not configured yet (single-target debug builds).
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func dir(_ name: String) -> URL {
        let url = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Temporary card images (deleted automatically once a person is finished).
    static var imagesDir: URL { dir("TempImages") }
    /// Batch state JSON (resume after crash / audit log).
    static var batchesDir: URL { dir("Batches") }
    /// Voice notes kept in-app (when the Contacts notes entitlement is not available).
    static var notesDir: URL { dir("VoiceNotes") }

    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

enum NameStyle: String, CaseIterable, Identifiable {
    case latinFirst, cjkFirst
    var id: String { rawValue }
}

/// User settings (App Group defaults). The API key lives in the Keychain, not here.
enum AppSettings {
    private static var d: UserDefaults { AppGroup.defaults }

    static var defaultRegion: String {
        get { d.string(forKey: "defaultRegion") ?? (Locale.current.region?.identifier ?? "CA") }
        set { d.set(newValue, forKey: "defaultRegion") }
    }
    /// Accuracy first: Claude vision + second opinion. Off = on-device only (Vision OCR + rules).
    static var useCloudAI: Bool {
        get { d.object(forKey: "useCloudAI") as? Bool ?? true }
        set { d.set(newValue, forKey: "useCloudAI") }
    }
    static var secondOpinion: Bool {
        get { d.object(forKey: "secondOpinion") as? Bool ?? true }
        set { d.set(newValue, forKey: "secondOpinion") }
    }
    static var extractionModel: String {
        get { d.string(forKey: "extractionModel") ?? "claude-opus-5-5" }
        set { d.set(newValue, forKey: "extractionModel") }
    }
    static var verifierModel: String {
        get { d.string(forKey: "verifierModel") ?? "claude-opus-5-5" }
        set { d.set(newValue, forKey: "verifierModel") }
    }
    static var nameStyle: NameStyle {
        get { NameStyle(rawValue: d.string(forKey: "nameStyle") ?? "") ?? .latinFirst }
        set { d.set(newValue.rawValue, forKey: "nameStyle") }
    }
    /// Only enable after Apple granted com.apple.developer.contacts.notes to your App ID.
    static var contactsNotesEntitled: Bool {
        get { d.bool(forKey: "contactsNotesEntitled") }
        set { d.set(newValue, forKey: "contactsNotesEntitled") }
    }
    static var onboardingDone: Bool {
        get { d.bool(forKey: "onboardingDone") }
        set { d.set(newValue, forKey: "onboardingDone") }
    }
}
