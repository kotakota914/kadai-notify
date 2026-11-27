import Foundation

/// 提出物の種類(課題・レポート・小テスト、Moodle や paiza で出る課題など)。
/// 追加・編集画面で選べるほか、課題名からおおよその種類を推測できる。
public enum AssignmentKind: String, CaseIterable, Sendable {
    case assignment   // 課題
    case report       // レポート
    case quiz         // 小テスト
    case survey       // アンケート
    case moodle       // Moodle(学習サイト)で出る課題
    case paiza        // paiza(プログラミング学習サイト)で出る課題
    case other        // その他

    /// 画面に出す名前
    public var label: String {
        switch self {
        case .assignment: return "課題"
        case .report: return "レポート"
        case .quiz: return "小テスト"
        case .survey: return "アンケート"
        case .moodle: return "Moodle"
        case .paiza: return "paiza"
        case .other: return "その他"
        }
    }

    /// 課題名から種類を推測する。当てはまる言葉がなければ「課題」。
    /// 例: 「第2回学習確認問題」→ 小テスト、「【レポート1】…」→ レポート
    public static func guess(fromTitle title: String) -> AssignmentKind {
        let text = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        // サイトの名前が入っていれば、そのサイトの課題とみなす(ほかの言葉より優先)
        if has(["moodle", "ムードル"]) { return .moodle }
        if has(["paiza", "パイザ"]) { return .paiza }
        if has(["アンケート", "survey"]) { return .survey }
        if has(["小テスト", "テスト", "クイズ", "確認問題", "quiz", "test"]) { return .quiz }
        if has(["レポート", "report"]) { return .report }
        if has(["ポートフォリオ", "自己評価", "自己点検"]) { return .other }
        return .assignment
    }
}

/// 提出物のランク(重要さ)。S がいちばん重要で、A・B・C の順に下がる。付けなくてもよい。
public enum AssignmentRank: String, CaseIterable, Comparable, Sendable {
    case s, a, b, c

    /// 画面に出す文字
    public var label: String { rawValue.uppercased() }

    /// 選ぶときに横に出す説明
    public var explanation: String {
        switch self {
        case .s: return "最重要"
        case .a: return "重要"
        case .b: return "ふつう"
        case .c: return "余裕があれば"
        }
    }

    /// 並べ替え用の順番(小さいほど重要)
    private var order: Int {
        switch self {
        case .s: return 0
        case .a: return 1
        case .b: return 2
        case .c: return 3
        }
    }

    /// 重要なほうが「小さい」(並べ替えると S が先頭に来る)
    public static func < (lhs: AssignmentRank, rhs: AssignmentRank) -> Bool { lhs.order < rhs.order }
}
