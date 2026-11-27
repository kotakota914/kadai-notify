import Foundation

/// 取り込みテキストから読み取れた課題 1 件
public struct ImportItem: Hashable, Sendable {
    public var subject: String
    public var title: String
    public var due: Date
    /// 締め切りに時刻が書いてあったか(false なら初期時刻 8:50 を使った)
    public var hasTime: Bool
    public var memo: String
    public var lineNumber: Int

    public init(subject: String, title: String, due: Date, hasTime: Bool, memo: String, lineNumber: Int) {
        self.subject = subject
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.memo = memo
        self.lineNumber = lineNumber
    }
}

/// 読み取れなかった行
public struct ImportError: Hashable, Sendable {
    public var lineNumber: Int
    public var line: String
    public var reason: String
}

/// 「#grading 科目名 | 評価方法」の行で指定された、科目の評価方法(配点)
public struct ImportGrading: Hashable, Sendable {
    public var subject: String
    public var note: String

    public init(subject: String, note: String) {
        self.subject = subject
        self.note = note
    }
}

public struct ImportResult: Sendable {
    public var items: [ImportItem]
    /// 「#subject 科目名」の行で指定された科目(課題がなくても登録しておきたい科目)。同じ名前は 1 回だけ
    public var subjects: [String] = []
    /// 「#grading 科目名 | 評価方法」の行。同じ科目が 2 回出てきたら後のものを使う
    public var gradings: [ImportGrading] = []
    /// 「#exam 科目 | テスト名 | 日時 | メモ」の行で指定されたテスト
    public var exams: [ImportExam] = []
    public var errors: [ImportError]
    /// 「#kadai v1」の行が見つかったか
    public var headerFound: Bool
}

/// Claude が出力した「#kadai v1」形式のテキストを読み取る。
///
///     #kadai v1
///     科目 | 課題名 | 2026-12-03 17:00 | メモ
public enum ImportParser {
    public static let header = "#kadai v1"

    /// Claude in Chrome への頼み方(設定画面からコピーできる)
    public static let claudePrompt = """
    学生ポータルの TODO / 課題一覧から、まだ締め切りが来ていない提出物を全部探して、
    次の形式だけを出力してください(説明文は不要)。

    #kadai v1
    科目 | 課題名 | 締め切り(YYYY-MM-DD HH:MM、時刻がわからなければ YYYY-MM-DD) | メモ

    - 1 行に 1 件
    - メモには提出方法など分かることを短く。なければ空欄
    - 「|」は区切り以外に使わない
    """

    public static func parse(_ text: String,
                             defaultHour: Int = 8,
                             defaultMinute: Int = 50,
                             calendar: Calendar) -> ImportResult {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // 「#kadai v1」の行を探す(Claude が前置きの文を付けても大丈夫なように、途中にあってもよい)
        guard let headerIndex = lines.firstIndex(where: {
            normalize($0).trimmingCharacters(in: .whitespaces).lowercased() == header
        }) else {
            return ImportResult(items: [], errors: [], headerFound: false)
        }

        var items: [ImportItem] = []
        var subjects: [String] = []
        var gradings: [ImportGrading] = []
        var exams: [ImportExam] = []
        var errors: [ImportError] = []

        for index in (headerIndex + 1)..<lines.count {
            let raw = lines[index]
            let lineNumber = index + 1
            let line = normalize(raw).trimmingCharacters(in: .whitespaces)

            // 「#subject 科目名」の行: 課題がなくても、その科目を登録する
            if let name = subjectName(fromDirective: line) {
                if !name.isEmpty, !subjects.contains(where: { ImportMatcher.key($0) == ImportMatcher.key(name) }) {
                    subjects.append(name)
                }
                continue
            }

            // 「#exam 科目 | テスト名 | 日時 | メモ」の行: テストを登録する
            if line.lowercased().hasPrefix("#exam ") || line.hasPrefix("#テスト ") {
                let body = line.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces)
                let parts = body.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 3, !parts[0].isEmpty, !parts[1].isEmpty,
                   let parsed = parseDate(parts[2], defaultHour: defaultHour, defaultMinute: defaultMinute, calendar: calendar) {
                    let memo = parts.dropFirst(3).filter { !$0.isEmpty }.joined(separator: " ")
                    exams.append(ImportExam(subject: parts[0], title: parts[1], date: parsed.0, hasTime: parsed.1, memo: memo))
                } else {
                    errors.append(ImportError(lineNumber: lineNumber, line: raw,
                                              reason: "テストは「#exam 科目 | テスト名 | 日時」の形で書きます"))
                }
                continue
            }

            // 「#grading 科目名 | 評価方法」の行: 科目の評価方法(配点)を登録する
            if line.lowercased().hasPrefix("#grading ") || line.hasPrefix("#評価 ") {
                let body = line.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces)
                // 評価方法の文の中に「|」があってもよいように、最初の 1 つだけで区切る
                let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                    gradings.removeAll { ImportMatcher.key($0.subject) == ImportMatcher.key(parts[0]) }
                    gradings.append(ImportGrading(subject: parts[0], note: parts[1]))
                } else {
                    errors.append(ImportError(lineNumber: lineNumber, line: raw,
                                              reason: "評価方法は「#grading 科目名 | 評価方法」の形で書きます"))
                }
                continue
            }

            // 空行・コメント行・コードブロックの記号(```)は読み飛ばす
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("```") { continue }

            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Claude が見出しの行(科目 | 課題名 | …)をそのまま出したときは読み飛ばす
            if columns.count >= 2, columns[0] == "科目", columns[1] == "課題名" { continue }

            guard columns.count >= 3 else {
                errors.append(ImportError(lineNumber: lineNumber, line: raw, reason: "「|」で区切られた項目が 3 つ未満です"))
                continue
            }
            let subject = columns[0]
            let title = columns[1]
            if subject.isEmpty {
                errors.append(ImportError(lineNumber: lineNumber, line: raw, reason: "科目が空です"))
                continue
            }
            if title.isEmpty {
                errors.append(ImportError(lineNumber: lineNumber, line: raw, reason: "課題名が空です"))
                continue
            }
            guard let parsed = parseDate(columns[2], defaultHour: defaultHour,
                                         defaultMinute: defaultMinute, calendar: calendar) else {
                errors.append(ImportError(lineNumber: lineNumber, line: raw, reason: "締め切り「\(columns[2])」を日付として読めません"))
                continue
            }
            let (due, hasTime) = parsed
            let memo = columns.dropFirst(3).filter { !$0.isEmpty }.joined(separator: " ")
            items.append(ImportItem(subject: subject, title: title, due: due, hasTime: hasTime,
                                    memo: memo, lineNumber: lineNumber))
        }
        return ImportResult(items: items, subjects: subjects, gradings: gradings, exams: exams, errors: errors, headerFound: true)
    }

    /// 「#subject 線形代数学」「#科目 線形代数学」の行なら科目名を返す。それ以外の行は nil。
    /// 「#」で始まる行は古い版では読み飛ばされるので、形式(v1)はそのままで足せる。
    static func subjectName(fromDirective line: String) -> String? {
        for prefix in ["#subject", "#科目"] {
            guard line.lowercased().hasPrefix(prefix) else { continue }
            let rest = line.dropFirst(prefix.count)
            // 「#subject線形代数学」のように区切りがない行は、ふつうのコメントとして扱う
            guard let first = rest.first, first == " " || first == ":" else { return rest.isEmpty ? "" : nil }
            return rest.drop(while: { $0 == " " || $0 == ":" }).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// 「2026-12-03 17:00」「2026/12/3」「2026-12-03T09:00」などを読む。
    /// 時刻がなければ (初期時刻, false) を返す。
    static func parseDate(_ text: String, defaultHour: Int, defaultMinute: Int,
                          calendar: Calendar) -> (Date, Bool)? {
        let parts = text.replacingOccurrences(of: "T", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 1 || parts.count == 2 else { return nil }

        let dateParts = parts[0].split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." })
            .compactMap { Int($0) }
        guard dateParts.count == 3 else { return nil }

        var hour = defaultHour
        var minute = defaultMinute
        let hasTime = parts.count == 2
        if hasTime {
            let timeParts = parts[1].split(separator: ":").compactMap { Int($0) }
            guard timeParts.count == 2 || timeParts.count == 3 else { return nil }
            hour = timeParts[0]
            minute = timeParts[1]
        }
        guard (1...12).contains(dateParts[1]), (1...31).contains(dateParts[2]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var comps = DateComponents()
        comps.year = dateParts[0]
        comps.month = dateParts[1]
        comps.day = dateParts[2]
        comps.hour = hour
        comps.minute = minute
        guard let date = calendar.date(from: comps) else { return nil }
        // 2 月 30 日のような存在しない日付は、繰り上がって別の日になるので弾く
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == dateParts[0], check.month == dateParts[1], check.day == dateParts[2] else { return nil }
        return (date, hasTime)
    }

    /// 全角の数字・記号・空白を半角にそろえる(「２０２６／１２／３」「｜」なども読めるように)
    static func normalize(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:   // 全角の英数字
                result.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0xFF5C: result.append("|")    // ｜
            case 0xFF1A: result.append(":")    // ：
            case 0xFF0F: result.append("/")    // ／
            case 0xFF0D, 0x2212: result.append("-")  // －, −
            case 0xFF0E: result.append(".")    // ．
            case 0xFF03: result.append("#")    // ＃
            case 0x3000: result.append(" ")    // 全角スペース
            case 0x09: result.append(" ")      // タブ
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

// MARK: - 重複の判定

/// すでに登録されている課題の情報(重複判定用)
public struct ExistingTaskKey: Hashable, Sendable {
    public var id: String
    public var subject: String
    public var title: String
    public var due: Date

    public init(id: String, subject: String, title: String, due: Date) {
        self.id = id
        self.subject = subject
        self.title = title
        self.due = due
    }
}

public enum ImportMatch: Hashable, Sendable {
    /// 新しい課題
    case new
    /// 同じものが登録済み(existingID が nil なら、同じテキストの中で 2 回出てきたもの)
    case duplicate(existingID: String?)
    /// 同じ課題で締め切り時刻だけ違う → 時刻を更新する
    case update(existingID: String)
}

public enum ImportMatcher {
    /// 「科目+課題名+締め切りの日付」が同じなら同じ課題とみなす。
    public static func matchAll(_ items: [ImportItem], existing: [ExistingTaskKey],
                                calendar: Calendar) -> [ImportMatch] {
        var seen: [ImportItem] = []
        return items.map { item in
            defer { seen.append(item) }
            if seen.contains(where: { sameTask($0.subject, $0.title, $0.due, item, calendar) }) {
                return .duplicate(existingID: nil)
            }
            guard let hit = existing.first(where: { sameTask($0.subject, $0.title, $0.due, item, calendar) }) else {
                return .new
            }
            // 時刻が同じ、または取り込み側に時刻が書いていない(手で直した時刻を優先)なら登録済み
            if abs(hit.due.timeIntervalSince(item.due)) < 60 || !item.hasTime {
                return .duplicate(existingID: hit.id)
            }
            return .update(existingID: hit.id)
        }
    }

    static func sameTask(_ subject: String, _ title: String, _ due: Date, _ item: ImportItem,
                         _ calendar: Calendar) -> Bool {
        key(subject) == key(item.subject) && key(title) == key(item.title)
            && calendar.isDate(due, inSameDayAs: item.due)
    }

    /// 比べるときは空白を消し、全角英数を半角に、英字を小文字にする(科目名の比較にも使う)
    public static func key(_ text: String) -> String {
        ImportParser.normalize(text).lowercased().filter { !$0.isWhitespace }
    }
}
