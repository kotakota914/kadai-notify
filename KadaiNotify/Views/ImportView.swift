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

    @State private var text = ""
    @State private var candidates: [Candidate] = []
    @State private var errors: [ImportError] = []
    @State private var parsed = false
    @State private var headerMissing = false

    private var selectedCount: Int { candidates.filter(\.selected).count }

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
                    Text("Mac の Claude in Chrome が出力した「#kadai v1」で始まる文字をコピーし、ここに貼り付けます。頼み方は「設定」タブからコピーできます。")
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

                    if !headerMissing && candidates.isEmpty && errors.isEmpty {
                        Section { Text("提出物の行がありませんでした。") }
                    }
                }
            }
            .navigationTitle("取り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\(selectedCount) 件を登録") { commit() }
                        .disabled(selectedCount == 0)
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
        parsed = true
    }

    private func commit() {
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
