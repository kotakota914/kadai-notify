import SwiftUI
import SwiftData
import KadaiCore

/// 提出物の追加・編集画面
struct AssignmentEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規追加
    let assignment: Assignment?

    // @State: この画面の中だけで使う、書き換えられる値
    @State private var subjectName: String
    @State private var title: String
    @State private var dueDate: Date
    @State private var memo: String
    @State private var kind: AssignmentKind
    /// 種類を自分で選んだか。選ぶまでは、課題名を打つたびに種類を推測し直す
    @State private var kindChosen: Bool
    /// ランク(重要さ)。nil = なし
    @State private var rank: AssignmentRank?
    /// 着手日を決めるか
    @State private var hasStart: Bool
    @State private var startDate: Date
    @State private var useCustomRules: Bool
    @State private var rules: [ReminderRule]
    @State private var confirmingDelete = false

    init(assignment: Assignment?) {
        self.assignment = assignment
        let settings = AppSettings.load()
        _subjectName = State(initialValue: assignment?.subject?.name ?? "")
        _title = State(initialValue: assignment?.title ?? "")
        _dueDate = State(initialValue: assignment?.dueDate ?? settings.defaultNewDueDate())
        _memo = State(initialValue: assignment?.memo ?? "")
        _kind = State(initialValue: assignment?.kind ?? .assignment)
        _kindChosen = State(initialValue: assignment?.kindRaw != nil)
        _rank = State(initialValue: assignment?.rank)
        _hasStart = State(initialValue: assignment?.startDate != nil)
        _startDate = State(initialValue: assignment?.startDate ?? Self.defaultStart())
        _useCustomRules = State(initialValue: assignment?.reminderRules != nil)
        _rules = State(initialValue: assignment?.reminderRules ?? [])
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 着手日の初期値: 今日の 9:00。もう過ぎていれば明日の 9:00
    private static func defaultStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let today9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        if today9 > now { return today9 }
        return calendar.date(byAdding: .day, value: 1, to: today9) ?? now
    }

    /// 種類の選択欄につなぐ値。自分で選んだら、その後は推測で上書きしない
    private var kindSelection: Binding<AssignmentKind> {
        Binding(get: { kind }, set: { kind = $0; kindChosen = true })
    }

    /// 課題ごとの設定がないときに使われるルール(科目 → 全体)
    private var inheritedRules: [ReminderRule] {
        let key = ImportMatcher.key(subjectName)
        let subject = try? context.fetch(FetchDescriptor<Subject>()).first { ImportMatcher.key($0.name) == key }
        return ReminderRule.resolve(task: nil, subject: subject?.reminderRules, global: AppSettings.load().globalRules)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("科目") {
                    SubjectPicker(name: $subjectName)
                }

                Section("提出物") {
                    TextField("課題名(例: 第8回レポート)", text: $title)
                    Picker("種類", selection: kindSelection) {
                        ForEach(AssignmentKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    // tag(…) に付ける値の型を、選択中の値(AssignmentRank?)と同じにそろえる
                    Picker("ランク", selection: $rank) {
                        Text("なし").tag(AssignmentRank?.none)
                        ForEach(AssignmentRank.allCases, id: \.self) { rank in
                            Text("\(rank.label)(\(rank.explanation))").tag(AssignmentRank?.some(rank))
                        }
                    }
                    DatePicker("締め切り", selection: $dueDate)
                    TextField("メモ(提出方法など)", text: $memo, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Toggle("着手日を決める", isOn: $hasStart)
                    if hasStart {
                        DatePicker("着手日", selection: $startDate)
                    }
                } footer: {
                    Text("取りかかり始める日時です。その時刻に通知が来て、ガントチャートの棒もここから始まります。")
                }

                Section {
                    Toggle("この課題だけ通知を変える", isOn: $useCustomRules)
                    if useCustomRules {
                        ReminderRulesEditor(rules: $rules)
                    } else {
                        Text("いまの設定: \(ReminderRule.summary(inheritedRules))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("オフのときは科目の設定、科目に設定がなければ全体の設定を使います。")
                }

                if assignment != nil {
                    Section {
                        Button("この提出物を削除", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(assignment == nil ? "提出物を追加" : "提出物を編集")
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
            .onChange(of: title) { _, newTitle in
                // 種類をまだ選んでいなければ、課題名から推測する(例: 「小テスト」と打つと種類も小テストになる)
                if !kindChosen { kind = AssignmentKind.guess(fromTitle: newTitle) }
            }
            .onChange(of: useCustomRules) { _, isOn in
                // オンにした瞬間は、いま使われている設定を出発点にする
                if isOn && rules.isEmpty { rules = inheritedRules.map { ReminderRule(kind: $0.kind, amount: $0.amount, hour: $0.hour, minute: $0.minute) } }
            }
            .confirmationDialog("この提出物を削除しますか?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { deleteAssignment() }
            }
        }
    }

    private func save() {
        let subject = SubjectService.findOrCreate(name: subjectName, in: context)
        let target: Assignment
        if let assignment {
            target = assignment
        } else {
            target = Assignment(title: "", dueDate: dueDate)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.dueDate = dueDate
        target.memo = memo
        // 自分で選んだときだけ種類を保存する(選んでいなければ、課題名からの推測のままにする)
        if kindChosen { target.kind = kind }
        target.rank = rank
        target.startDate = hasStart ? startDate : nil
        target.subject = subject
        target.reminderRules = useCustomRules ? rules : nil
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }

    private func deleteAssignment() {
        guard let assignment else { return }
        NotificationService.removeDelivered(forTaskKey: assignment.key)
        context.delete(assignment)
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }
}

/// 科目を選ぶ部品。登録済みの科目の一覧から選ぶ。
/// 一覧にない科目は「新しい科目を入力…」を選ぶと名前を打てる。
/// 科目が 1 つも登録されていないときは、最初から入力欄だけを出す。
struct SubjectPicker: View {
    /// 選ばれている(または入力中の)科目名
    @Binding var name: String
    @Query(sort: \Subject.name) private var subjects: [Subject]
    /// 「新しい科目を入力…」を選んでいる間は true
    @State private var typingNew = false

    /// 一覧の中で「未選択」「新しい科目」を表すための目印(科目名とぶつからない文字列)
    private static let noneTag = ""
    private static let newTag = "\u{0}new"

    /// いま一覧のどれが選ばれているか
    private var selection: Binding<String> {
        Binding(
            get: {
                if typingNew { return Self.newTag }
                // 空白や大文字小文字の違いは同じ科目とみなす(保存時の扱いと合わせる)
                if let found = subjects.first(where: { ImportMatcher.key($0.name) == ImportMatcher.key(name) }) {
                    return found.name
                }
                return name.isEmpty ? Self.noneTag : Self.newTag
            },
            set: { value in
                if value == Self.newTag {
                    typingNew = true
                    name = ""
                } else {
                    typingNew = false
                    name = value
                }
            }
        )
    }

    var body: some View {
        if subjects.isEmpty {
            TextField("科目名(例: 情報システム)", text: $name)
        } else {
            Picker("科目", selection: selection) {
                // 「選んでください」は、まだ何も選んでいない間だけ出す
                if selection.wrappedValue == Self.noneTag {
                    Text("選んでください").tag(Self.noneTag)
                }
                ForEach(subjects) { subject in
                    Text(subject.name).tag(subject.name)
                }
                Text("新しい科目を入力…").tag(Self.newTag)
            }
            if selection.wrappedValue == Self.newTag {
                TextField("新しい科目名", text: $name)
            }
        }
    }
}

#Preview {
    AssignmentEditView(assignment: nil)
        .modelContainer(PreviewData.container)
}
