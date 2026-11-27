import SwiftUI
import SwiftData
import KadaiCore

/// 「テスト」タブ。登録したテストを日付が近い順に並べ、「あと ○ 日」を大きく出す
struct ExamListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exam.date) private var exams: [Exam]

    @State private var editing: Exam?
    @State private var showingNew = false
    @State private var showPast = false

    var body: some View {
        NavigationStack {
            // 1 分ごとに描き直す(日付が変わったら残り日数も変わるように)
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                list(now: timeline.date)
            }
            .navigationTitle("テスト")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) { ExamEditView(exam: nil) }
            .sheet(item: $editing) { exam in ExamEditView(exam: exam) }
        }
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        let upcoming = exams.filter { $0.date > now }
        // 終わったテストは、新しいものから順に
        let past = exams.filter { $0.date <= now }.reversed()

        List {
            if upcoming.isEmpty {
                ContentUnavailableView("テストの予定はありません",
                                       systemImage: "graduationcap",
                                       description: Text("右上の + でテストの日を登録すると、残り日数を数えます。"))
            }

            ForEach(upcoming) { exam in
                ExamCard(exam: exam, now: now)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = exam }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(exam) } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
            }

            if !past.isEmpty {
                Section {
                    if showPast {
                        ForEach(Array(past)) { exam in
                            ExamCard(exam: exam, now: now)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = exam }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(exam) } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Button {
                        withAnimation { showPast.toggle() }
                    } label: {
                        HStack {
                            Text("終わったテスト(\(past.count))")
                            Image(systemName: showPast ? "chevron.down" : "chevron.right")
                        }
                    }
                }
            }
        }
    }

    private func delete(_ exam: Exam) {
        context.delete(exam)
        try? context.save()
        Refresher.refresh(context)
    }
}

/// テスト 1 件分のカード。右側に残り日数を大きく出す
struct ExamCard: View {
    let exam: Exam
    let now: Date

    private let calendar = Calendar.current

    var body: some View {
        let days = ExamCountdown.daysLeft(until: exam.date, now: now, calendar: calendar)
        let finished = exam.date <= now

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: exam.subject?.colorHex ?? "#999999"))
                        .frame(width: 8, height: 8)
                    Text(exam.subject?.name ?? "科目なし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(exam.title)
                    .font(.headline)
                    .foregroundStyle(finished ? Color.secondary : Color.primary)
                Text(DeadlineText.dateTime(exam.date, calendar: calendar))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !finished && days <= 1 {
                    // 前日・当日は、残り時間も出す(例: 「あと 3 時間」)
                    Text(DeadlineText.remaining(until: exam.date, now: now))
                        .font(.caption.bold())
                        .foregroundStyle(ExamStyle.color(daysLeft: days))
                }
                if !exam.memo.isEmpty {
                    Text(exam.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            countdown(days: days, finished: finished)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// 残り日数を、輪っかの中に出す。テストが近づくほど輪っかが埋まり、色も強くなる
    @ViewBuilder
    private func countdown(days: Int, finished: Bool) -> some View {
        let color = finished ? Color.secondary : ExamStyle.color(daysLeft: days)
        // 14 日前から埋まり始め、当日にいっぱいになる
        let progress = finished ? 1.0 : min(1, max(0.04, 1 - Double(days) / 14))

        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))   // 真上から時計回りに埋める

            if finished {
                Image(systemName: "checkmark")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            } else if days >= 2 {
                VStack(spacing: -3) {
                    Text("\(days)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("日")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                // 「明日」「今日」
                Text(days == 1 ? "明日" : "今日")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 72, height: 72)
        .padding(.vertical, 2)
    }
}

/// テストの追加・編集画面
struct ExamEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規追加
    let exam: Exam?

    @State private var subjectName: String
    @State private var title: String
    @State private var date: Date
    @State private var memo: String
    @State private var confirmingDelete = false

    init(exam: Exam?) {
        self.exam = exam
        _subjectName = State(initialValue: exam?.subject?.name ?? "")
        _title = State(initialValue: exam?.title ?? "")
        _date = State(initialValue: exam?.date ?? Self.defaultDate())
        _memo = State(initialValue: exam?.memo ?? "")
    }

    /// 日時の初期値: 7 日後の 9:00
    private static func defaultDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("科目") {
                    SubjectPicker(name: $subjectName)
                }

                Section("テスト") {
                    TextField("テスト名(例: 期末試験)", text: $title)
                    DatePicker("日時", selection: $date)
                    TextField("メモ(範囲、持ち込みなど)", text: $memo, axis: .vertical)
                        .lineLimit(2...6)
                }

                if exam != nil {
                    Section {
                        Button("このテストを削除", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(exam == nil ? "テストを追加" : "テストを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("このテストを削除しますか?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { deleteExam() }
            }
        }
    }

    private func save() {
        let target: Exam
        if let exam {
            target = exam
        } else {
            target = Exam(title: "", date: date)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.date = date
        target.memo = memo
        // 科目は選ばなくてもよい(選ばなければ「科目なし」)
        target.subject = SubjectService.findOrCreate(name: subjectName, in: context)
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }

    private func deleteExam() {
        guard let exam else { return }
        context.delete(exam)
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }
}

#Preview {
    ExamListView()
        .modelContainer(PreviewData.container)
}
