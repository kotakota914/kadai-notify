import Foundation
import SwiftData
import KadaiCore

// このファイルは「アプリ」と「ウィジェット」の両方で使う、保存するデータの形(モデル)。
// @Model を付けたクラスは SwiftData(Apple 標準のデータ保存の仕組み)が自動で保存してくれる。
// 項目に初期値を書いておくと、あとで項目を増やしたときに古いデータを読み込みやすい。

/// 科目
@Model
final class Subject {
    var uid: UUID = UUID()
    var name: String = ""
    /// 色("#RRGGBB")
    var colorHex: String = "#0090FF"
    /// 科目ごとの通知ルール(JSON)。nil なら全体の設定を使う
    var reminderRulesData: Data?
    var createdAt: Date = Date()
    /// 評価方法(配点)のメモ。例: 「レポート 40% / 小テスト 30% / 期末試験 30%」。空なら未登録
    var gradingNote: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Assignment.subject)
    var assignments: [Assignment]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTemplate.subject)
    var templates: [RecurringTemplate]? = []

    @Relationship(deleteRule: .nullify, inverse: \Exam.subject)
    var exams: [Exam]? = []

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }

    /// 通知ルール(nil = 指定なし)
    var reminderRules: [ReminderRule]? {
        get { ReminderRule.decodeList(reminderRulesData) }
        set { reminderRulesData = newValue.map(ReminderRule.encodeList) }
    }

    /// 未完了の課題の数
    var pendingCount: Int {
        (assignments ?? []).filter { !$0.isDone }.count
    }
}

/// 課題がどこから来たか
enum AssignmentSource: String {
    case manual      // 手入力
    case imported    // 取り込み
    case recurring   // 繰り返しから自動作成
}

/// 課題(提出物 1 件)
@Model
final class Assignment {
    var uid: UUID = UUID()
    var title: String = ""
    var dueDate: Date = Date()
    var memo: String = ""
    var isDone: Bool = false
    var completedAt: Date?
    /// 課題ごとの通知ルール(JSON)。nil なら科目 → 全体の設定を使う
    var reminderRulesData: Data?
    var sourceRaw: String = AssignmentSource.manual.rawValue
    var createdAt: Date = Date()
    /// 種類(課題・小テストなど)。nil なら、まだ選んでいないので課題名から推測する。
    /// あとから足した項目なので、古いデータを読めるように「なくてもよい」(nil を許す)形にしている
    var kindRaw: String?
    /// ランク(重要さ。S・A・B・C)。nil なら付けていない
    var rankRaw: String?
    /// 着手日(取りかかり始める予定の日時)。nil なら決めていない
    var startDate: Date?

    var subject: Subject?
    var template: RecurringTemplate?

    init(title: String, dueDate: Date, memo: String = "", source: AssignmentSource = .manual) {
        self.title = title
        self.dueDate = dueDate
        self.memo = memo
        self.sourceRaw = source.rawValue
    }

    var reminderRules: [ReminderRule]? {
        get { ReminderRule.decodeList(reminderRulesData) }
        set { reminderRulesData = newValue.map(ReminderRule.encodeList) }
    }

    var source: AssignmentSource {
        AssignmentSource(rawValue: sourceRaw) ?? .manual
    }

    /// 種類。自分で選んでいればそれを、選んでいなければ課題名からの推測を返す
    var kind: AssignmentKind {
        get { kindRaw.flatMap(AssignmentKind.init(rawValue:)) ?? AssignmentKind.guess(fromTitle: title) }
        set { kindRaw = newValue.rawValue }
    }

    /// ランク(重要さ)。付けていなければ nil
    var rank: AssignmentRank? {
        get { rankRaw.flatMap(AssignmentRank.init(rawValue:)) }
        set { rankRaw = newValue?.rawValue }
    }

    /// 通知の識別に使う文字列
    var key: String { uid.uuidString }
}

/// テスト(試験)1 件。提出物とは別に持ち、「あと何日」を数える
@Model
final class Exam {
    var uid: UUID = UUID()
    var title: String = ""
    /// テストの日時
    var date: Date = Date()
    /// 範囲や持ち込みなどのメモ
    var memo: String = ""
    var createdAt: Date = Date()

    var subject: Subject?

    init(title: String, date: Date, memo: String = "") {
        self.title = title
        self.date = date
        self.memo = memo
    }

    /// 通知の識別に使う文字列
    var key: String { uid.uuidString }
}

/// 毎週の繰り返し課題のひな形
@Model
final class RecurringTemplate {
    var uid: UUID = UUID()
    /// 課題名のひな形。「{n}」が回数に置き換わる
    var titlePattern: String = ""
    /// 曜日(1 = 日曜 … 7 = 土曜)
    var weekday: Int = 5
    var hour: Int = 17
    var minute: Int = 0
    var startDate: Date = Date()
    var endDate: Date?
    var isActive: Bool = true
    /// これまでに作った最後の回の締め切り(削除された回を作り直さないために使う)
    var lastGeneratedDue: Date?
    var createdAt: Date = Date()

    var subject: Subject?

    @Relationship(deleteRule: .nullify, inverse: \Assignment.template)
    var assignments: [Assignment]? = []

    init(titlePattern: String, weekday: Int, hour: Int, minute: Int, startDate: Date, endDate: Date?) {
        self.titlePattern = titlePattern
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.startDate = startDate
        self.endDate = endDate
    }

    var weeklyRule: WeeklyRule {
        WeeklyRule(weekday: weekday, hour: hour, minute: minute,
                   startDate: startDate, endDate: endDate, titlePattern: titlePattern)
    }

    /// 例: 「毎週 木曜 17:00」
    var scheduleLabel: String {
        "毎週 \(DeadlineText.weekdaySymbol(weekday))曜 \(hour):\(String(format: "%02d", minute))"
    }
}
