import SwiftUI
import SwiftData
import KadaiCore

/// Claude が出力した「#kadai v1」形式のテキストを貼り付けて、まとめて登録する画面
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 確認画面に並べる 1 件分
    struct Candidate: Identifiable {
        let id = UUID()
        var item: ImportItem
        var match: ImportMatch
        var selected: Bool
    }

    @State private var text: String
    @State private var candidates: [Candidate] = []
    @State private var errors: [ImportError] = []
    /// 「#subject 科目名」の行で指定された科目のうち、まだ登録されていないもの
    @State private var newSubjects: [String] = []
    /// 同じく、すでに登録されていたものの数
    @State private var knownSubjectCount = 0
    /// 「#grading 科目名 | 評価方法」の行で指定された、科目の評価方法(配点)
    @State private var gradings: [ImportGrading] = []
    @State private var parsed = false
    @State private var headerMissing = false

    private var selectedCount: Int { candidates.filter(\.selected).count }
    /// 提出物のほかに、登録する科目や評価方法があるか
    private var hasExtras: Bool { !newSubjects.isEmpty || !gradings.isEmpty }

    /// - Parameter initialText: 最初から入れておくテキスト。Mac から送られてきたファイルの中身を渡すと、
    ///   画面を開いた時点で読み取りまで済ませる。何も渡さなければ空の画面から始まる。
    init(initialText: String = "") {
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // PasteButton: 押したときだけクリップボードを読む(毎回の許可ダイアログが出ない)
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in
                            text = strings.joined(separator: "\n")
                            parse()
                        }
                    }
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                    Button("読み取る") { parse() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("取り込むテキスト")
                } footer: {
                    Text("Mac の Claude in Chrome が出力した「#kadai v1」で始まる文字をコピーし、ここに貼り付けます。頼み方は、提出物の画面の右上にある歯車(設定)からコピーできます。")
                }

                if parsed {
                    if headerMissing {
                        Section {
                            Label("「#kadai v1」の行が見つかりません。Claude の出力をそのまま貼り付けてください。",
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }

                    if !candidates.isEmpty {
                        Section {
                            ForEach($candidates) { $candidate in
                                CandidateRow(candidate: $candidate)
                            }
                        } header: {
                            Text("登録する提出物(\(selectedCount) 件)")
                        } footer: {
                            Text("左の丸でチェックを外したものは登録しません。登録済みのものは最初からチェックを外しています。")
                        }
                    }

                    if !newSubjects.isEmpty || knownSubjectCount > 0 {
                        Section {
                            ForEach(newSubjects, id: \.self) { name in
                                Label(name, systemImage: "plus.circle")
                            }
                            if knownSubjectCount > 0 {
                                Text("登録済みの科目 \(knownSubjectCount) 件はそのままにします")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("追加する科目(\(newSubjects.count) 件)")
                        } footer: {
                            Text("提出物を追加するときに、科目の一覧から選べるようになります。色はあとで変えられます。")
                        }
                    }

                    if !gradings.isEmpty {
                        Section {
                            ForEach(gradings, id: \.self) { grading in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(grading.subject).font(.subheadline.bold())
                                    Text(grading.note)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("評価方法(配点)を登録する科目(\(gradings.count) 件)")
                        } footer: {
                            Text("提出物を長押しすると見られます。すでに書いてある評価方法は、この内容で置き換わります。")
                        }
                    }

                    if !errors.isEmpty {
                        Section("読み取れなかった行(登録しません)") {
                            ForEach(errors, id: \.lineNumber) { error in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(error.lineNumber) 行目: \(error.reason)")
                                        .foregroundStyle(.red)
                                    Text(error.line)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !headerMissing && candidates.isEmpty && errors.isEmpty
                        && newSubjects.isEmpty && knownSubjectCount == 0 && gradings.isEmpty {
                        Section { Text("提出物の行がありませんでした。") }
                    }
                }
            }
            .navigationTitle("取り込み")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Mac から送られてきたテキストが最初から入っているときは、すぐ読み取る
                if !parsed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parse() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 提出物がなく、科目や評価方法だけのときは「登録」と出す
                    Button(selectedCount == 0 && hasExtras ? "登録" : "\(selectedCount) 件を登録") { commit() }
                        .disabled(selectedCount == 0 && !hasExtras)
                }
            }
        }
    }

    private func parse() {
        let settings = AppSettings.load()
        let calendar = Calendar.current
        let result = ImportParser.parse(text,
                                        defaultHour: settings.defaultDueMinutes / 60,
                                        defaultMinute: settings.defaultDueMinutes % 60,
                                        calendar: calendar)
        let existing = (try? context.fetch(FetchDescriptor<Assignment>())) ?? []
        let keys = existing.map {
            ExistingTaskKey(id: $0.key, subject: $0.subject?.name ?? "", title: $0.title, due: $0.dueDate)
        }
        let matches = ImportMatcher.matchAll(result.items, existing: keys, calendar: calendar)
        candidates = zip(result.items, matches).map { item, match in
            let isDuplicate: Bool
            if case .duplicate = match { isDuplicate = true } else { isDuplicate = false }
            return Candidate(item: item, match: match, selected: !isDuplicate)
        }
        errors = result.errors
        headerMissing = !result.headerFound

        // 「#subject」の行の科目を、まだない科目と登録済みの科目に分ける
        let knownKeys = Set(((try? context.fetch(FetchDescriptor<Subject>())) ?? []).map { ImportMatcher.key($0.name) })
        newSubjects = result.subjects.filter { !knownKeys.contains(ImportMatcher.key($0)) }
        knownSubjectCount = result.subjects.count - newSubjects.count
        gradings = result.gradings
        parsed = true
    }

    private func commit() {
        // 先に科目を作る(提出物がなくても、科目の一覧から選べるようにするため)
        for name in newSubjects {
            _ = SubjectService.findOrCreate(name: name, in: context)
        }
        // 科目の評価方法(配点)を書き込む(科目がなければ作る)
        for grading in gradings {
            SubjectService.findOrCreate(name: grading.subject, in: context)?.gradingNote = grading.note
        }
        let existing = (try? context.fetch(FetchDescriptor<Assignment>())) ?? []
        for candidate in candidates where candidate.selected {
            let item = candidate.item
            if case .update(let id) = candidate.match, let target = existing.first(where: { $0.key == id }) {
                // 同じ課題で締め切りの時刻だけ違う → 時刻を直す(確認画面で直した科目・課題名も反映)
                target.dueDate = item.due
                target.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                target.subject = SubjectService.findOrCreate(name: item.subject, in: context) ?? target.subject
                if !item.memo.isEmpty { target.memo = item.memo }
            } else {
                let subject = SubjectService.findOrCreate(name: item.subject, in: context)
                let assignment = Assignment(title: item.title, dueDate: item.due, memo: item.memo, source: .imported)
                context.insert(assignment)
                assignment.subject = subject
            }
        }
        try? context.save()
        Refresher.refresh(context)
        dismiss()
    }
}

/// 確認画面の 1 行。科目・課題名・締め切りはこの場で直せる
private struct CandidateRow: View {
    @Binding var candidate: ImportView.Candidate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                candidate.selected.toggle()
            } label: {
                Image(systemName: candidate.selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(candidate.selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.text)
                    .font(.caption2.bold())
                    .foregroundStyle(status.color)
                TextField("科目", text: $candidate.item.subject)
                    .font(.caption)
                TextField("課題名", text: $candidate.item.title)
                    .font(.headline)
                DatePicker("締め切り", selection: $candidate.item.due)
                    .font(.subheadline)
                if !candidate.item.hasTime {
                    Text("時刻が書かれていなかったので初期時刻にしています")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if !candidate.item.memo.isEmpty {
                    Text(candidate.item.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var status: (text: String, color: Color) {
        switch candidate.match {
        case .new: return ("新規", .green)
        case .duplicate(let id): return (id == nil ? "このテキスト内で重複" : "登録済み", .secondary)
        case .update: return ("登録済み・締め切りの時刻を更新", .orange)
        }
    }
}

#Preview {
    ImportView()
        .modelContainer(PreviewData.container)
}
