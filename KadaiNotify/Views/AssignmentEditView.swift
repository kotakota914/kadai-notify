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
        _useCustomRules = State(initialValue: assignment?.reminderRules != nil)
        _rules = State(initialValue: assignment?.reminderRules ?? [])
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    TextField("科目名(例: 情報システム)", text: $subjectName)
                    SubjectChips(selection: $subjectName)
                }

                Section("提出物") {
                    TextField("課題名(例: 第8回レポート)", text: $title)
                    DatePicker("締め切り", selection: $dueDate)
                    TextField("メモ(提出方法など)", text: $memo, axis: .vertical)
                        .lineLimit(2...6)
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

/// 登録済みの科目を横に並べ、タップで選べるようにする
struct SubjectChips: View {
    @Binding var selection: String
    @Query(sort: \Subject.name) private var subjects: [Subject]

    var body: some View {
        if !subjects.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(subjects) { subject in
                        Button {
                            selection = subject.name
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: subject.colorHex)).frame(width: 8, height: 8)
                                Text(subject.name).font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selection == subject.name ? Color(hex: subject.colorHex) : .gray)
                    }
                }
            }
        }
    }
}

#Preview {
    AssignmentEditView(assignment: nil)
        .modelContainer(PreviewData.container)
}
