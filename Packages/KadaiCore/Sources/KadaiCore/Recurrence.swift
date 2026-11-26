import Foundation

/// 毎週の繰り返し課題のルール。例: 毎週木曜 17:00 締め切り「第{n}回 小テスト」
public struct WeeklyRule: Hashable, Sendable {
    /// 曜日(Calendar と同じ: 1 = 日曜, 2 = 月曜, … 7 = 土曜)
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    /// この日から数え始める(1 回目 = この日以降で最初の該当曜日)
    public var startDate: Date
    /// この日まで(その日を含む)。nil なら終わりなし
    public var endDate: Date?
    /// 課題名のひな形。「{n}」は回数(1, 2, 3 …)に置き換わる
    public var titlePattern: String

    public init(weekday: Int, hour: Int, minute: Int, startDate: Date, endDate: Date?, titlePattern: String) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.startDate = startDate
        self.endDate = endDate
        self.titlePattern = titlePattern
    }
}

/// 繰り返しから作られる 1 回分
public struct Occurrence: Hashable, Sendable {
    public var due: Date
    public var number: Int
    public var title: String
}

public enum RecurrenceGenerator {
    /// 何日先の分まで作るか(要件: 2 週分 = 14 日)
    public static let lookaheadDays = 14

    /// 新しく作るべき回を返す。
    /// - 締め切りが「今」より後、かつ「今から 14 日以内」
    /// - lastGeneratedDue(前回までに作った最後の回)より後
    ///   → 一度作った回は、ユーザーが削除しても作り直さない
    public static func occurrences(rule: WeeklyRule, lastGeneratedDue: Date?, now: Date,
                                   calendar: Calendar) -> [Occurrence] {
        guard (1...7).contains(rule.weekday),
              let firstDay = firstOccurrenceDay(rule: rule, calendar: calendar) else { return [] }
        let limit = now.addingTimeInterval(TimeInterval(lookaheadDays * 24 * 3600))
        let endDay = rule.endDate.map { calendar.startOfDay(for: $0) }

        var result: [Occurrence] = []
        var week = 0
        while week < 1000 {   // 念のための上限(約 19 年分)
            defer { week += 1 }
            guard let day = calendar.date(byAdding: .day, value: week * 7, to: firstDay),
                  let due = calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: day)
            else { break }
            if due > limit { break }
            if let endDay, calendar.startOfDay(for: due) > endDay { break }
            if due <= now { continue }
            if let last = lastGeneratedDue, due <= last { continue }
            let number = week + 1
            let title = rule.titlePattern.replacingOccurrences(of: "{n}", with: String(number))
            result.append(Occurrence(due: due, number: number, title: title))
        }
        return result
    }

    /// 開始日以降で最初の該当曜日(0:00)
    static func firstOccurrenceDay(rule: WeeklyRule, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: rule.startDate)
        let startWeekday = calendar.component(.weekday, from: start)
        let diff = (rule.weekday - startWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: diff, to: start)
    }
}
