import Foundation

/// テスト(試験)までの残り日数を、画面に出す形にする。
/// 「日」は時刻ではなく日付で数える(今日が月曜で、テストが水曜なら、朝でも夜でも「あと 2 日」)。
public enum ExamCountdown {
    /// テストの日まで、日付で数えてあと何日か。今日なら 0、明日なら 1、過ぎた日なら負の数
    public static func daysLeft(until date: Date, now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let examDay = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: examDay).day ?? 0
    }

    /// 一覧に出す文字。例: 「あと 6 日」「明日」「今日(あと 3 時間)」「終了」
    public static func text(until date: Date, now: Date, calendar: Calendar) -> String {
        if date <= now { return "終了" }
        switch daysLeft(until: date, now: now, calendar: calendar) {
        case 0: return "今日(\(DeadlineText.remaining(until: date, now: now)))"
        case 1: return "明日"
        case let days: return "あと \(days) 日"
        }
    }
}

/// 通知の計算に必要な、テスト 1 件分の情報
public struct ExamSnapshot: Hashable, Sendable {
    public var id: String
    public var subject: String
    public var title: String
    public var date: Date

    public init(id: String, subject: String, title: String, date: Date) {
        self.id = id
        self.subject = subject
        self.title = title
        self.date = date
    }
}

/// 取り込みテキストの「#exam 科目 | テスト名 | 日時 | メモ」の行から読み取ったテスト
public struct ImportExam: Hashable, Sendable {
    public var subject: String
    public var title: String
    public var date: Date
    /// 日時に時刻が書いてあったか(false なら初期時刻を使った)
    public var hasTime: Bool
    public var memo: String

    public init(subject: String, title: String, date: Date, hasTime: Bool, memo: String) {
        self.subject = subject
        self.title = title
        self.date = date
        self.hasTime = hasTime
        self.memo = memo
    }
}
