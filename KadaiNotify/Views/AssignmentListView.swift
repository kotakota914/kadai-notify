import SwiftUI
import SwiftData
import KadaiCore

/// 提出物の一覧(期限切れ / 今日 / 明日 / それ以降 / 完了済み)
struct AssignmentListView: View {
    @Environment(\.modelContext) private var context

    // @Query: データベースから条件に合うものを取り出し、変わったら画面も自動で更新する
    @Query(filter: #Predicate<Assignment> { $0.isDone == false }, sort: \Assignment.dueDate)
    private var pending: [Assignment]
    @Query(filter: #Predicate<Assignment> { $0.isDone == true })
    private var done: [Assignment]

    @State private var editing: Assignment?
    @State private var showingNew = false
    @State private var showingImport = false
    @State private var showingSettings = false
    @State private var showDone = false

    var body: some View {
        NavigationStack {
            // TimelineView で 1 分ごとに描き直す → 開いたまま締め切りを過ぎても「期限切れ」に移る
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                list(now: timeline.date)
            }
            .navigationTitle("提出物")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingImport = true } label: {
                        Label("取り込み", systemImage: "square.and.arrow.down")
                    }
                }
                // 右上: 歯車(設定)と +(追加)。書いた順に左から並ぶので、+ がいちばん右に来る
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                    Button { showingNew = true } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingNew) { AssignmentEditView(assignment: nil) }
            .sheet(item: $editing) { assignment in AssignmentEditView(assignment: assignment) }
            .sheet(isPresented: $showingImport) { ImportView() }
        }
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        let calendar = Calendar.current
        // 締め切りの近い順のまま、グループごとに分ける
        let groups = Dictionary(grouping: pending) { DueGroup.group(for: $0.dueDate, now: now, calendar: calendar) }
        let doneSorted = done.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        List {
            if let expiry = SigningInfo.expirationDate, expiry.timeIntervalSince(now) < 2 * 24 * 3600 {
                Section { SigningExpiryBanner(expiry: expiry, now: now) }
            }

            if pending.isEmpty {
                ContentUnavailableView("提出物はありません",
                                       systemImage: "checkmark.seal",
                                       description: Text("右上の + で追加、左上の「取り込み」で Claude の出力から一括登録できます。"))
            }

            ForEach(DueGroup.allCases, id: \.self) { group in
                if let items = groups[group], !items.isEmpty {
                    Section {
                        ForEach(items) { row($0, now: now) }
                    } header: {
                        Text("\(group.title)(\(items.count))")
                            .foregroundStyle(group == .overdue ? Color.red : Color.secondary)
                    }
                }
            }

            if !doneSorted.isEmpty {
                Section {
                    if showDone {
                        ForEach(doneSorted) { row($0, now: now) }
                    }
                } header: {
                    Button {
                        withAnimation { showDone.toggle() }
                    } label: {
                        HStack {
                            Text("完了済み(\(doneSorted.count))")
                            Image(systemName: showDone ? "chevron.down" : "chevron.right")
                        }
                    }
                }
            }
        }
    }

    private func row(_ assignment: Assignment, now: Date) -> some View {
        AssignmentRow(assignment: assignment, now: now) { toggleDone(assignment) }
            .contentShape(Rectangle())
            .onTapGesture { editing = assignment }
            // 長押し: 提出物の詳しい内容と、その科目の評価方法(配点)をカードで出す
            .contextMenu {
                Button { editing = assignment } label: { Label("編集", systemImage: "pencil") }
                Button { toggleDone(assignment) } label: {
                    Label(assignment.isDone ? "未完了に戻す" : "完了にする",
                          systemImage: assignment.isDone ? "arrow.uturn.backward" : "checkmark")
                }
            } preview: {
                AssignmentPeekView(assignment: assignment, now: now)
            }
            .swipeActions(edge: .leading) {
                Button { toggleDone(assignment) } label: {
                    Label(assignment.isDone ? "未完了に戻す" : "完了",
                          systemImage: assignment.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { delete(assignment) } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }

    private func toggleDone(_ assignment: Assignment) {
        AssignmentActions.toggleDone(assignment, in: context)
    }

    private func delete(_ assignment: Assignment) {
        NotificationService.removeDelivered(forTaskKey: assignment.key)
        context.delete(assignment)
        try? context.save()
        Refresher.refresh(context)
    }
}

/// 一覧の 1 行
struct AssignmentRow: View {
    let assignment: Assignment
    let now: Date
    let onToggle: () -> Void

    var body: some View {
        let group = DueGroup.group(for: assignment.dueDate, now: now, calendar: .current)
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(assignment.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)   // 行のタップ(編集)とは別に押せるようにする
            .accessibilityLabel(assignment.isDone ? "未完了に戻す" : "完了にする")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: assignment.subject?.colorHex ?? "#999999"))
                        .frame(width: 8, height: 8)
                    Text(assignment.subject?.name ?? "科目なし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // 種類(課題・小テストなど)を小さな札で出す
                    Text(assignment.kind.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    if let rank = assignment.rank { RankBadge(rank: rank) }
                    if assignment.template != nil {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(assignment.title)
                    .font(.headline)
                    .strikethrough(assignment.isDone)
                    .foregroundStyle(assignment.isDone ? Color.secondary : Color.primary)
                Text(DeadlineText.dateTime(assignment.dueDate, calendar: .current))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !assignment.isDone {
                Text(DeadlineText.remaining(until: assignment.dueDate, now: now))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(group.color)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 提出物を長押ししたときに出すカード。締め切り・種類・ランクと、その科目の評価方法(配点)を見せる
struct AssignmentPeekView: View {
    let assignment: Assignment
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: assignment.subject?.colorHex ?? "#999999"))
                        .frame(width: 10, height: 10)
                    Text(assignment.subject?.name ?? "科目なし")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(assignment.title)
                    .font(.title3.bold())
                HStack(spacing: 6) {
                    if let rank = assignment.rank { RankBadge(rank: rank) }
                    Text(assignment.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("締め切り").font(.caption.bold()).foregroundStyle(.secondary)
                Text("\(DeadlineText.dateTime(assignment.dueDate, calendar: .current))(\(DeadlineText.remaining(until: assignment.dueDate, now: now)))")
                    .font(.subheadline)
            }

            if let start = assignment.startDate {
                VStack(alignment: .leading, spacing: 2) {
                    Text("着手日").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(DeadlineText.dateTime(start, calendar: .current)).font(.subheadline)
                }
            }

            if !assignment.memo.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("メモ").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(assignment.memo).font(.subheadline)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("評価方法(配点)").font(.caption.bold()).foregroundStyle(.secondary)
                if let note = assignment.subject?.gradingNote, !note.isEmpty {
                    Text(note).font(.subheadline)
                } else {
                    Text("まだ登録されていません。「科目・繰り返し」タブで科目を開くと書き込めます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(width: 330, alignment: .leading)
    }
}

/// 署名の期限が近いときに一覧の上に出す注意
struct SigningExpiryBanner: View {
    let expiry: Date
    let now: Date

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(expiry > now ? "アプリの署名期限が近づいています" : "アプリの署名期限が切れています")
                    .font(.subheadline.bold())
                Text("期限: \(DeadlineText.dateTime(expiry, calendar: .current))。Mac の Xcode から入れ直してください(データは消えません)。")
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    AssignmentListView()
        .modelContainer(PreviewData.container)
}
