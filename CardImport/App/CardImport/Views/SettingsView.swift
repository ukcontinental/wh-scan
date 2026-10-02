import SwiftUI
import CardCore

struct SettingsView: View {
    var highlightKey: Bool
    var onClose: () -> Void
    @State private var apiKey = KeychainStore.load() ?? ""
    @State private var useCloud = AppSettings.useCloudAI
    @State private var secondOpinion = AppSettings.secondOpinion
    @State private var region = AppSettings.defaultRegion
    @State private var nameStyle = AppSettings.nameStyle
    @State private var notesEntitled = AppSettings.contactsNotesEntitled
    @State private var model = AppSettings.extractionModel
    @State private var verifier = AppSettings.verifierModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Anthropic API 金鑰") } footer: {
                    Text(highlightKey ? "要用 AI 辨識，請先貼上金鑰（console.anthropic.com → API Keys）。只存在這支手機的鑰匙圈。"
                                      : "金鑰只存在這支手機的鑰匙圈。")
                }
                Section {
                    Toggle("AI 辨識（最準確）", isOn: $useCloud)
                    Toggle("不確定的欄位交給第二個模型複核", isOn: $secondOpinion).disabled(!useCloud)
                    Picker("主要模型", selection: $model) {
                        Text("Claude Opus 5.5（預設）").tag("claude-opus-5-5")
                        Text("Claude Fable 5.1（最強、較貴）").tag("claude-fable-5-1")
                        Text("Claude Sonnet 5.5（較快、較便宜）").tag("claude-sonnet-5-5")
                    }.disabled(!useCloud)
                    Picker("複核模型", selection: $verifier) {
                        Text("Claude Opus 5.5（預設）").tag("claude-opus-5-5")
                        Text("Claude Fable 5.1（最強、較貴）").tag("claude-fable-5-1")
                    }.disabled(!useCloud || !secondOpinion)
                } header: { Text("辨識") } footer: {
                    Text("關閉 AI 辨識時只用手機內建的文字辨識（免費、不上傳）。為了不寫錯資料，幾乎每位聯絡人都需要你確認。斷網不需要關閉 AI：沒有網路時批次會暫停，連線後自動繼續。AI 成本估計每張照片約 US$0.05–0.12（含複核），以實測為準。")
                }
                Section("聯絡人") {
                    Picker("預設國家/地區（電話沒寫國碼時）", selection: $region) {
                        Text("加拿大 CA").tag("CA"); Text("美國 US").tag("US"); Text("台灣 TW").tag("TW")
                        Text("中國 CN").tag("CN"); Text("香港 HK").tag("HK")
                    }
                    Picker("中英文姓名都有時", selection: $nameStyle) {
                        Text("英文名為主，中文名放「暱稱」").tag(NameStyle.latinFirst)
                        Text("中文名為主，英文名放「暱稱」").tag(NameStyle.cjkFirst)
                    }
                    Toggle("可寫入「備註」欄位（需 Apple 核准）", isOn: $notesEntitled)
                }
                Section("NFC 一碰開始") {
                    Text("""
                    1. 打開「捷徑」→「自動化」→「＋」→「NFC」。
                    2. 掃描你的 NFC 貼紙並命名。
                    3. 動作選「匯入名片」（本 App 提供）。
                    4. 選「立即執行」，關閉「執行時通知」。
                    之後用 iPhone 碰貼紙，就會直接打開照片多選畫面。
                    """).font(.footnote)
                }
                Section("處理紀錄") {
                    NavigationLink("最近的匯入批次") { ProcessingLogView() }
                }
                Section("隱私") {
                    Text("從「照片」選的原始照片不會被刪除或修改。App 只在處理期間保存暫存縮圖，完成後自動刪除；有待確認項目的照片會保留到你確認完。開啟 AI 辨識時，照片會傳到 Anthropic API 處理。")
                        .font(.footnote)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save(); onClose() }
                }
            }
        }
    }

    func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { KeychainStore.delete() } else { KeychainStore.save(trimmed) }
        AppSettings.useCloudAI = useCloud
        AppSettings.secondOpinion = secondOpinion
        AppSettings.defaultRegion = region
        AppSettings.nameStyle = nameStyle
        AppSettings.contactsNotesEntitled = notesEntitled
        AppSettings.extractionModel = model
        AppSettings.verifierModel = verifier
    }
}

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var apiKey = ""
    @State private var contactsGranted = ContactsService.authorized

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("一次設定，之後只要「選照片」。").font(.headline)
                }
                Section("1. AI 金鑰") {
                    SecureField("貼上 Anthropic API 金鑰", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("2. 聯絡人權限") {
                    Button(contactsGranted ? "已允許 ✓" : "允許取用聯絡人") {
                        Task { contactsGranted = await ContactsService().requestAccess() }
                    }.disabled(contactsGranted)
                    if ContactsService.isLimited {
                        Text("目前是「有限取用」：重複聯絡人檢查只看得到你分享的聯絡人。建議改為完整取用。").font(.footnote)
                    }
                }
                Section("3. NFC（選用）") {
                    Text("「捷徑」→「自動化」→ NFC → 動作「匯入名片」→「立即執行」。").font(.footnote)
                }
            }
            .navigationTitle("名片匯入")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("開始使用") {
                        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !k.isEmpty { KeychainStore.save(k) }
                        AppSettings.onboardingDone = true
                        onDone()
                    }
                }
            }
        }
    }
}

/// Audit log: what each batch did. Read-only; never part of the import flow.
struct ProcessingLogView: View {
    @EnvironmentObject var engine: ImportEngine
    @State private var batches: [BatchState] = []

    var body: some View {
        List(batches, id: \.id) { b in
            let s = b.summary
            VStack(alignment: .leading, spacing: 4) {
                Text(b.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Text("照片 \(s.photos)・人數 \(s.peopleDetected)・新建 \(s.created)・更新 \(s.updated)・已存在 \(s.alreadyExisted)")
                    .font(.footnote)
                Text("待確認 \(s.openReviewItems)・失敗 \(s.failedPhotos)・US$\(String(format: "%.2f", s.costUSD))・\(Int(s.seconds)) 秒・\(b.source)")
                    .font(.footnote).foregroundStyle(.secondary)
                if b.phase != .done { Text("狀態：\(b.phase.rawValue)").font(.footnote).foregroundStyle(.orange) }
            }
        }
        .overlay { if batches.isEmpty { Text("尚無紀錄").foregroundStyle(.secondary) } }
        .navigationTitle("處理紀錄")
        .task { batches = await engine.recentBatches() }
    }
}
