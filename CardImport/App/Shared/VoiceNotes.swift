import SwiftUI
import Speech
import AVFoundation
import CardCore

/// Optional: dictate "where we met / what they look like / what they want" for a just-imported contact.
/// Never part of the batch flow, so it costs nothing when unused.
@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var text = ""
    @Published var recording = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(locale: Locale = Locale(identifier: "zh-TW")) async {
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK, let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            error = "需要麥克風與語音辨識權限"; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            request = req
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            recording = true
            text = ""
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    if let result { self?.text = result.bestTranscription.formattedString }
                    if err != nil || (result?.isFinal ?? false) { self?.stop() }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        guard recording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

struct VoiceNotePeopleView: View {
    let state: BatchState
    @Environment(\.dismiss) private var dismiss

    var people: [PersonRecord] { state.people.filter { ($0.status == .created || $0.status == .updated) && $0.contactIdentifier != nil } }

    var body: some View {
        NavigationStack {
            List(people, id: \.id) { p in
                NavigationLink(p.fullDraft?.displayName ?? p.id) { VoiceNoteView(person: p) }
            }
            .navigationTitle("語音備註")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct VoiceNoteView: View {
    let person: PersonRecord
    @StateObject private var speech = SpeechTranscriber()
    @State private var structured = ""
    @State private var saving = false
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section("說說這個人") {
                Text(speech.text.isEmpty ? "例如：在 Toronto Food Show 認識，做食品進口，戴眼鏡，對冷凍食品有興趣。" : speech.text)
                    .foregroundStyle(speech.text.isEmpty ? .secondary : .primary)
                Button {
                    if speech.recording { speech.stop() } else { Task { await speech.start() } }
                } label: {
                    Label(speech.recording ? "停止" : "開始錄音", systemImage: speech.recording ? "stop.circle.fill" : "mic.circle.fill")
                }
                if let e = speech.error { Text(e).foregroundStyle(.red).font(.footnote) }
            }
            if !structured.isEmpty { Section("將寫入的備註") { Text(structured).font(.callout) } }
            Section {
                Button(saving ? "整理中…" : "整理並儲存") { Task { await save() } }
                    .disabled(speech.text.isEmpty || saving || speech.recording)
                if let m = savedMessage { Text(m).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(person.fullDraft?.displayName ?? "")
    }

    func save() async {
        saving = true
        defer { saving = false }
        let transcript = speech.text
        var note = "Voice note: \(transcript)"
        if AppSettings.useCloudAI, let key = KeychainStore.load(), !key.isEmpty {
            if let s = try? await VoiceNoteStructurer(client: ClaudeClient(config: ClaudeConfig(apiKey: key))).structure(transcript: transcript) {
                note = s
            }
        }
        structured = note
        let stamped = "[\(Date().formatted(date: .abbreviated, time: .omitted))]\n" + note
        guard let id = person.contactIdentifier else { return }
        let contacts = ContactsService()
        do {
            try contacts.appendNote(stamped, to: id)
            savedMessage = "已寫入聯絡人的「備註」。"
        } catch {
            // Without Apple's notes entitlement the note is kept in the app (searchable there).
            let url = AppGroup.notesDir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".txt")
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (existing.isEmpty ? stamped : existing + "\n\n" + stamped).write(to: url, atomically: true, encoding: .utf8)
            savedMessage = "已存在 App 內（寫入通訊錄備註需 Apple 核准的權限，見設定）。"
        }
    }
}
