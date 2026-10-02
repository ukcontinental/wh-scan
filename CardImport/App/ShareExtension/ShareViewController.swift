import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CardCore

/// Photos → Select → Share → 名片匯入. Runs the same pipeline inside the share sheet with a progress view.
/// If the sheet is closed early, the batch is persisted and the app resumes it on next launch.
final class ShareViewController: UIViewController {
    private let engine = ImportEngine()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRootView(engine: engine, close: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        Task { @MainActor in
            // Without Contacts access in the extension: recognise now, the app writes the contacts later.
            engine.stopBeforeWriting = !ContactsService.authorized
            var datas: [Data] = []
            for p in providers {
                if let d = await Self.load(p) { datas.append(d) }
            }
            await engine.importImages(datas, source: "share")
        }
    }

    static func load(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in cont.resume(returning: data) }
        }
    }
}

struct ShareRootView: View {
    @ObservedObject var engine: ImportEngine
    var close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch engine.stage {
                case .idle, .preparing:
                    WorkingPanel(title: "準備照片…", detail: "")
                case .processing(let p):
                    WorkingPanel(title: p.phase == "finalizing" ? "建立聯絡人…" : "辨識名片…",
                                 detail: p.peopleTotal > 0 ? "\(p.peopleDone) / \(p.peopleTotal) 位" : "\(p.recognized) / \(p.total) 張")
                case .finished:
                    if let s = engine.state {
                        if engine.stopBeforeWriting {
                            VStack(spacing: 14) {
                                Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(.green)
                                Text("已辨識 \(s.people.count) 位").font(.title2.bold())
                                Text("打開「名片匯入」App 一次以允許聯絡人權限，聯絡人就會自動建立。")
                                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                Button("完成", action: close).buttonStyle(.borderedProminent)
                            }.padding(28)
                        } else {
                            CompletionView(state: s, onDone: close, allowVoiceNotes: false).environmentObject(engine)
                        }
                    }
                case .needsAPIKey:
                    MessagePanel(text: "請先打開「名片匯入」App 設定 API 金鑰。", close: close)
                case .needsContactsAccess:
                    MessagePanel(text: "請先打開「名片匯入」App 允許聯絡人權限。", close: close)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("關閉", action: close) } }
        }
    }
}

struct WorkingPanel: View {
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(title).font(.title3.bold())
            Text(detail).monospacedDigit().foregroundStyle(.secondary)
            Text("關閉也沒關係，下次打開 App 會自動接續。").font(.footnote).foregroundStyle(.secondary)
        }.padding(28)
    }
}

struct MessagePanel: View {
    var text: String
    var close: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text(text).multilineTextAlignment(.center)
            Button("關閉", action: close).buttonStyle(.borderedProminent)
        }.padding(28)
    }
}
