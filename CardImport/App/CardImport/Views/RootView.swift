import SwiftUI
import PhotosUI
import CardCore

struct RootView: View {
    @EnvironmentObject var engine: ImportEngine
    @EnvironmentObject var router: ImportRouter
    @State private var selection: [PhotosPickerItem] = []
    @State private var showSettings = false
    @State private var showOnboarding = !AppSettings.onboardingDone && DemoData.requestedScreen() == nil

    var body: some View {
        NavigationStack {
            Group {
                switch engine.stage {
                case .idle:
                    HomeView(showSettings: $showSettings)
                case .preparing(let done, let total):
                    WorkingView(title: "準備照片…", detail: "\(done) / \(total)", fraction: total == 0 ? 0 : Double(done) / Double(total))
                case .processing(let p):
                    WorkingView(title: p.phase == "finalizing" ? "建立聯絡人…" : "辨識名片…",
                                detail: p.peopleTotal > 0 ? "\(p.peopleDone) / \(p.peopleTotal) 位" : "\(p.recognized) / \(p.total) 張",
                                fraction: p.peopleTotal > 0 ? 0.6 + 0.4 * Double(p.peopleDone) / Double(max(1, p.peopleTotal))
                                                            : 0.6 * Double(p.recognized) / Double(max(1, p.total)))
                case .finished:
                    if let s = engine.state {
                        CompletionView(state: s, autoOpenReview: DemoData.requestedScreen() == "review")
                    } else { HomeView(showSettings: $showSettings) }
                case .needsAPIKey:
                    SettingsView(highlightKey: true, onClose: { engine.reset() })
                case .needsContactsAccess:
                    ContactsAccessView()
                }
            }
            .toolbar {
                if case .idle = engine.stage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
            }
        }
        .photosPicker(isPresented: $router.showPicker, selection: $selection, maxSelectionCount: nil,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            let source = router.pendingSource
            selection = []
            Task {
                // Load each photo only when it is about to be prepared (selection order is kept).
                let loaders: [@Sendable () async -> Data?] = items.map { item in { try? await item.loadTransferable(type: Data.self) } }
                await engine.importImages(loaders: loaders, source: source)
            }
        }
        .onChange(of: router.pendingImages) { _, images in
            guard let images, !images.isEmpty else { return }
            router.pendingImages = nil
            Task { await engine.importImages(images, source: router.pendingSource) }
        }
        .task {
            // Images handed over by a Shortcut before this view existed.
            if let images = router.pendingImages, !images.isEmpty {
                router.pendingImages = nil
                await engine.importImages(images, source: router.pendingSource)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(highlightKey: false, onClose: { showSettings = false }).environmentObject(engine) }
        .fullScreenCover(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
    }
}

struct HomeView: View {
    @EnvironmentObject var router: ImportRouter
    @EnvironmentObject var engine: ImportEngine
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 28) {
            if let p = engine.pendingReview {
                Button {
                    engine.openPendingReview()
                } label: {
                    Label("上次匯入還有 \(p.review.filter { !$0.resolved }.count) 項待確認", systemImage: "exclamationmark.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.orange).padding(.horizontal, 24).padding(.top, 8)
            }
            Spacer()
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 64)).foregroundStyle(.tint)
            Text("名片匯入").font(.largeTitle.bold())
            Text("選好名片照片，其餘交給系統").foregroundStyle(.secondary)
            Button {
                router.requestPicker(source: "app")
            } label: {
                Label("選擇名片照片", systemImage: "photo.on.rectangle.angled")
                    .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 32)
            Spacer()
            Text("提示：在「捷徑」設定 NFC 自動化，碰一下就會直接打開照片選擇。")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
        .padding(.bottom)
    }
}

struct WorkingView: View {
    var title: String
    var detail: String
    var fraction: Double

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(value: min(max(fraction, 0), 1)).progressViewStyle(.linear).padding(.horizontal, 48)
            Text(title).font(.title2.bold())
            Text(detail).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            Text("可以離開這個畫面，處理會繼續；中斷後重新打開會從中斷處接續。")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
    }
}

struct ContactsAccessView: View {
    @EnvironmentObject var engine: ImportEngine
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark").font(.system(size: 54)).foregroundStyle(.orange)
            Text("需要「聯絡人」權限").font(.title2.bold())
            Text("系統要讀取通訊錄來避免建立重複聯絡人，並寫入新的聯絡人。請到「設定」允許「完整取用」。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("打開設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.buttonStyle(.borderedProminent)
            Button("返回") { engine.reset() }
        }.padding(32)
    }
}
