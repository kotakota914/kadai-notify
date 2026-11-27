import SwiftUI
import SwiftData
import KadaiCore

/// 科目と毎週の繰り返し課題の一覧
struct SubjectListView: View {
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \RecurringTemplate.createdAt) private var templates: [RecurringTemplate]

    @State private var editingSubject: Subject?
    @State private var addingSubject = false
    @State private var editingTemplate: RecurringTemplate?
    @State private var addingTemplate = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if subjects.isEmpty {
                        Text("まだ科目がありません。提出物を追加すると自動で作られます。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(subjects) { subject in
                        Button { editingSubject = subject } label: {
                            HStack {
                                Circle().fill(Color(hex: subject.colorHex)).frame(width: 12, height: 12)
                                Text(subject.name)
                                Spacer()
                                if subject.reminderRules != nil {
                                    Image(systemName: "bell.badge").foregroundStyle(.secondary)
                                }
                                Text("未完了 \(subject.pendingCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("科目")
                } footer: {
                    Text("科目ごとに色と通知のタイミングを決められます(🔔 = 科目専用の通知設定あり)。")
                }

                Section {
                    if templates.isEmpty {
                        Text("例: 毎週木曜 17:00 締め切りの小テスト")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(templates) { template in
                        Button { editingTemplate = template } label: {
                            HStack {
                                Circle().fill(Color(hex: template.subject?.colorHex ?? "#999999")).frame(width: 12, height: 12)
                                VStack(alignment: .leading) {
                                    Text(template.titlePattern)
                                    Text("\(template.subject?.name ?? "科目なし") ・ \(template.scheduleLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !template.isActive {
                                    Text("停止中").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Button { addingTemplate = true } label: {
                        Label("繰り返しを追加", systemImage: "plus.circle")
                    }
                } header: {
                    Text("毎週の繰り返し課題")
                } footer: {
                    Text("締め切りが 14 日以内の回が、自動で提出物に追加されます。")
                }
            }
            .navigationTitle("科目・繰り返し")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingSubject = true } label: { Label("科目を追加", systemImage: "plus") }
                }
            }
            .sheet(item: $editingSubject) { SubjectEditView(subject: $0) }
            .sheet(isPresented: $addingSubject) { SubjectEditView(subject: nil) }
            .sheet(item: $editingTemplate) { TemplateEditView(template: $0) }
            .sheet(isPresented: $addingTemplate) { TemplateEditView(template: nil) }
        }
    }
}

/// 科目の追加・編集(名前・色・通知)
struct SubjectEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let subject: Subject?

    @State private var name: String
    @State private var colorHex: String
    /// 評価方法(配点)のメモ
    @State private var gradingNote: String
    @State private var useCustomRules: Bool
    @State private var rules: [ReminderRule]
    @State private var message: String?
    @State private var messageTitle = "保存できません"
    @State private var confirmingDelete = false

    init(subject: Subject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _colorHex = State(initialValue: subject?.colorHex ?? SubjectPalette.colors[5])
        _gradingNote = State(initialValue: subject?.gradingNote ?? "")
        _useCustomRules = State(initialValue: subject?.reminderRules != nil)
        _rules = State(initialValue: subject?.reminderRules ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("科目名") {
                    TextField("例: 情報システム", text: $name)
                }

                Section("色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(Array(SubjectPalette.colors.enumerated()), id: \.offset) { index, hex in
                            Button { colorHex = hex } label: {
                                ZStack {
                                    Circle().fill(Color(hex: hex)).frame(width: 36, height: 36)
                                    if colorHex.uppercased() == hex.uppercased() {
                                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(SubjectPalette.names[index])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("例: レポート 40% / 小テスト 30% / 期末試験 30%", text: $gradingNote, axis: .vertical)
                        .lineLimit(2...8)
                } header: {
                    Text("評価方法(配点)")
                } footer: {
                    Text("学習支援計画書(シラバス)の配点を書いておくと、提出物を長押ししたときに見られます。")
                }

                Section {
                    Toggle("この科目だけ通知を変える", isOn: $useCustomRules)
                    if useCustomRules {
                        ReminderRulesEditor(rules: $rules)
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("例: 重いレポートが多い科目は「7 日前の 21:00」を足す。オフなら全体の設定を使います。")
                }

                if subject != nil {
                    Section {
                        Button("この科目を削除", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("提出物や繰り返しが残っている科目は削除できません。")
                    }
                }
            }
            .navigationTitle(subject == nil ? "科目を追加" : "科目を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: useCustomRules) { _, isOn in
                if isOn && rules.isEmpty {
                    rules = AppSettings.load().globalRules.map {
                        ReminderRule(kind: $0.kind, amount: $0.amount, hour: $0.hour, minute: $0.minute)
                    }
                }
            }
            .alert(messageTitle, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .confirmationDialog("この科目を削除しますか?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { deleteSubject() }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        if all.contains(where: { ImportMatcher.key($0.name) == ImportMatcher.key(trimmed) && $0 !== subject }) {
            messageTitle = "保存できません"
            message = "「\(trimmed)」という科目はすでにあります。"
            return
        }
        let target: Subject
        if let subject {
            target = subject
        } else {
            target = Subject(name: trimmed, colorHex: colorHex)
            context.insert(target)
        }
        target.name = trimmed
        target.colorHex = colorHex
        target.gradingNote = gradingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        target.reminderRules = useCustomRules ? rules : nil
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }

    private func deleteSubject() {
        guard let subject else { return }
        if !(subject.assignments ?? []).isEmpty || !(subject.templates ?? []).isEmpty {
            messageTitle = "削除できません"
            message = "この科目の提出物(完了済みも含む)や繰り返しが残っています。先に削除するか、別の科目に変えてください。"
            return
        }
        context.delete(subject)
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }
}

/// 毎週の繰り返し課題の追加・編集
struct TemplateEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let template: RecurringTemplate?

    @State private var subjectName: String
    @State private var titlePattern: String
    @State private var weekday: Int
    @State private var hour: Int
    @State private var minute: Int
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var isActive: Bool
    @State private var confirmingDelete = false

    init(template: RecurringTemplate?) {
        self.template = template
        _subjectName = State(initialValue: template?.subject?.name ?? "")
        _titlePattern = State(initialValue: template?.titlePattern ?? "第{n}回 ")
        _weekday = State(initialValue: template?.weekday ?? 5)
        _hour = State(initialValue: template?.hour ?? 17)
        _minute = State(initialValue: template?.minute ?? 0)
        _startDate = State(initialValue: template?.startDate ?? .now)
        _hasEndDate = State(initialValue: template?.endDate != nil)
        _endDate = State(initialValue: template?.endDate
                         ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _isActive = State(initialValue: template?.isActive ?? true)
    }

    private var canSave: Bool {
        !subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !titlePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("科目") {
                    SubjectPicker(name: $subjectName)
                }

                Section {
                    TextField("例: 第{n}回 小テスト", text: $titlePattern)
                } header: {
                    Text("課題名")
                } footer: {
                    Text("{n} は回数(1, 2, 3 …)に置き換わります。開始日以降の最初の回が 1 回目です。")
                }

                Section("締め切り") {
                    Picker("曜日", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text("\(DeadlineText.weekdaySymbol(day))曜日").tag(day)
                        }
                    }
                    DatePicker("時刻", selection: timeBinding(hour: $hour, minute: $minute),
                               displayedComponents: .hourAndMinute)
                    DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                    Toggle("終了日を決める", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("終了日(学期末)", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("有効", isOn: $isActive)
                } footer: {
                    Text("オフにすると新しい回を作らなくなります。作成済みの提出物は残ります。")
                }

                if template != nil {
                    Section {
                        Button("この繰り返しを削除", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("作成済みの提出物は残ります。")
                    }
                }
            }
            .navigationTitle(template == nil ? "繰り返しを追加" : "繰り返しを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("この繰り返しを削除しますか?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { deleteTemplate() }
            }
        }
    }

    private func save() {
        let subject = SubjectService.findOrCreate(name: subjectName, in: context)
        let newEnd = hasEndDate ? endDate : nil
        let pattern = titlePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: RecurringTemplate
        if let template {
            target = template
            let scheduleChanged = template.weekday != weekday || template.hour != hour || template.minute != minute
                || template.startDate != startDate || template.endDate != newEnd || template.titlePattern != pattern
            if scheduleChanged {
                // 日程を変えたら、これから先の未完了の回を消して作り直す
                for assignment in template.assignments ?? [] where !assignment.isDone && assignment.dueDate > .now {
                    context.delete(assignment)
                }
                template.lastGeneratedDue = nil
            }
        } else {
            target = RecurringTemplate(titlePattern: pattern, weekday: weekday, hour: hour, minute: minute,
                                       startDate: startDate, endDate: newEnd)
            context.insert(target)
        }
        target.titlePattern = pattern
        target.weekday = weekday
        target.hour = hour
        target.minute = minute
        target.startDate = startDate
        target.endDate = newEnd
        target.isActive = isActive
        target.subject = subject
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }

    private func deleteTemplate() {
        guard let template else { return }
        context.delete(template)
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }
}

#Preview {
    SubjectListView()
        .modelContainer(PreviewData.container)
}
