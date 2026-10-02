import SwiftUI
import CardCore

/// The only screen after a batch: counts, "Review N" (if any) and "Done".
struct CompletionView: View {
    @EnvironmentObject var engine: ImportEngine
    let state: BatchState
    var onDone: (() -> Void)? = nil
    var allowVoiceNotes = true
    var autoOpenReview = false
    @State private var showReview = false
    @State private var showNotes = false

    var body: some View {
        let s = state.summary
        VStack(spacing: 22) {
            Spacer(minLength: 12)
            Image(systemName: statusIcon(s)).font(.system(size: 56)).foregroundStyle(statusColor(s))
            Text(title(s)).font(.title.bold())
            VStack(alignment: .leading, spacing: 10) {
                row("照片", s.photos)
                row("偵測到人數", s.peopleDetected)
                row("新建聯絡人", s.created)
                if s.updated > 0 { row("更新既有聯絡人", s.updated) }
                if s.alreadyExisted > 0 { row("已存在（略過）", s.alreadyExisted) }
                row("待確認", s.openReviewItems, highlight: s.openReviewItems > 0)
                if s.failedPhotos > 0 { row("無法辨識的照片", s.failedPhotos, highlight: true) }
            }
            .font(.title3)
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            if state.phase == .pausedOffline {
                Label("目前沒有網路，恢復連線後會自動繼續。", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
            }
            if state.phase == .pausedAuth {
                Label("API 金鑰無效，請到設定更新。", systemImage: "key.slash").font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            VStack(spacing: 12) {
                if s.openReviewItems > 0 {
                    Button { showReview = true } label: {
                        Text("確認 \(s.openReviewItems) 項").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent)
                }
                if s.failedPhotos > 0 {
                    Button("重試 \(s.failedPhotos) 張") { Task { await engine.retryFailed() } }
                }
                Button {
                    if let onDone { onDone() } else { engine.reset() }
                } label: {
                    Text("完成").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.bordered)
                if allowVoiceNotes && s.created + s.updated > 0 {
                    Button("加語音備註（選用）") { showNotes = true }.font(.footnote)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showReview) { ReviewView().environmentObject(engine) }
        .onAppear { if autoOpenReview { showReview = true } }
        .sheet(isPresented: $showNotes) { VoiceNotePeopleView(state: state) }
    }

    func row(_ label: String, _ n: Int, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(n)").monospacedDigit().bold().foregroundStyle(highlight ? Color.orange : Color.primary)
        }
    }

    func title(_ s: BatchSummary) -> String {
        switch state.phase {
        case .pausedOffline: return "等待網路"
        case .pausedAuth: return "需要 API 金鑰"
        default: return s.openReviewItems == 0 ? "匯入完成" : "匯入完成，剩 \(s.openReviewItems) 項待確認"
        }
    }

    func statusIcon(_ s: BatchSummary) -> String {
        if state.phase == .pausedOffline { return "wifi.slash" }
        if state.phase == .pausedAuth { return "key.slash" }
        return s.openReviewItems == 0 ? "checkmark.circle.fill" : "checkmark.circle.badge.questionmark"
    }

    func statusColor(_ s: BatchSummary) -> Color {
        if state.phase == .pausedAuth { return .red }
        return s.openReviewItems == 0 && state.phase == .done ? .green : .orange
    }
}

/// Only the uncertain fields — never the whole card.
struct ReviewView: View {
    @EnvironmentObject var engine: ImportEngine
    @Environment(\.dismiss) private var dismiss

    var open: [ReviewItem] { engine.state?.review.filter { !$0.resolved } ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if open.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
                        Text("全部確認完成").font(.title2.bold())
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(open) { item in ReviewCard(item: item, personName: personName(item)) }
                        }.padding()
                    }
                }
            }
            .navigationTitle("待確認 \(open.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    func personName(_ item: ReviewItem) -> String {
        engine.state?.people.first { $0.id == item.personID }?.fullDraft?.displayName ?? ""
    }
}

struct ReviewCard: View {
    @EnvironmentObject var engine: ImportEngine
    let item: ReviewItem
    let personName: String
    @State private var custom = ""
    @State private var editing = false
    @State private var zoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !personName.isEmpty { Text(personName).font(.headline) }
            Text(item.question).font(.subheadline).foregroundStyle(.secondary)
            if let first = item.photoIDs.first, let img = engine.images.image(first) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: zoom ? 420 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { withAnimation { zoom.toggle() } }
            }
            ForEach(item.candidates, id: \.self) { c in
                Button { submit(c) } label: {
                    Text(display(c)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.buttonStyle(.bordered)
            }
            HStack {
                if item.kind == .field {
                    Button(editing ? "取消" : "自行輸入") { editing.toggle(); custom = item.candidates.first ?? "" }
                    Spacer()
                    Button("留空") { submit(nil) }.foregroundStyle(.secondary)
                }
            }.font(.footnote)
            if editing {
                HStack {
                    TextField("正確內容", text: $custom).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    Button("確定") { submit(custom) }.disabled(custom.isEmpty)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    func display(_ c: String) -> String {
        if let bar = c.firstIndex(of: "|") { return String(c[c.index(after: bar)...]) }
        return c
    }

    func submit(_ value: String?) {
        Task { await engine.answer(item, with: value) }
    }
}
