import Foundation

/// 月のカレンダー(マス目)を作るための計算。
public enum MonthGrid {
    /// その日が入っている月の 1 日(0:00)
    public static func firstOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// n か月ずらした月の 1 日(n は負でもよい)
    public static func addingMonths(_ n: Int, to date: Date, calendar: Calendar) -> Date {
        let first = firstOfMonth(date, calendar: calendar)
        return calendar.date(byAdding: .month, value: n, to: first) ?? first
    }

    /// カレンダーのマス目に並べる日付。週の始まり(日本では日曜)から、月の最後の日が入る週の終わりまで。
    /// 前後の月の日も含むので、数はいつも 7 の倍数(28・35・42 のどれか)になる。
    public static func days(inMonthOf date: Date, calendar: Calendar) -> [Date] {
        let first = firstOfMonth(date, calendar: calendar)
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        // 1 日の前に、前の月の日がいくつ並ぶか
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let cells = Int((Double(leading + daysInMonth) / 7).rounded(.up)) * 7
        return (0..<cells).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: first) }
    }

    /// 曜日の見出し(週の始まりから 7 つ)。例: ["日", "月", "火", "水", "木", "金", "土"]
    public static func weekdayHeaders(calendar: Calendar) -> [String] {
        (0..<7).map { DeadlineText.weekdaySymbol(calendar.firstWeekday + $0) }
    }

    /// 例: 「2026年11月」
    public static func title(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }
}

/// ガントチャート(横棒で期間を表す図)の棒 1 本の位置。単位は「日」。
public struct GanttBar: Equatable, Sendable {
    /// 表示範囲の左端から、棒の左端までの日数
    public let offsetDays: Double
    /// 棒の長さ(日数)
    public let lengthDays: Double
    /// 始まりが表示範囲より前にはみ出している
    public let startsBeforeRange: Bool
    /// 終わりが表示範囲より後にはみ出している
    public let endsAfterRange: Bool
}

/// ガントチャートの計算。
public enum GanttLayout {
    private static let day: TimeInterval = 24 * 3600

    /// 棒が短すぎて見えなくならないための最小の長さ(日)
    public static let minimumLengthDays = 0.5

    /// 始まり(start)から締め切り(end)までの棒が、表示範囲のどこに来るかを計算する。
    /// 表示範囲にまったく入らないときは nil。
    /// - Parameters:
    ///   - rangeStart: 表示範囲の左端(その日の 0:00)
    ///   - rangeDays: 表示範囲の日数
    public static func bar(start: Date, end: Date, rangeStart: Date, rangeDays: Int) -> GanttBar? {
        let total = Double(rangeDays)
        // 始まりが締め切りより後(締め切り後に登録したなど)なら、締め切りの位置に短い棒を出す
        let rawStart = min(start, end).timeIntervalSince(rangeStart) / day
        let rawEnd = end.timeIntervalSince(rangeStart) / day
        guard rawEnd > 0, rawStart < total else { return nil }

        let clampedEnd = min(rawEnd, total)
        var clampedStart = max(rawStart, 0)
        if clampedEnd - clampedStart < minimumLengthDays {
            clampedStart = max(clampedEnd - minimumLengthDays, 0)
        }
        return GanttBar(offsetDays: clampedStart,
                        lengthDays: max(clampedEnd - clampedStart, min(minimumLengthDays, total)),
                        startsBeforeRange: rawStart < 0,
                        endsAfterRange: rawEnd > total)
    }

    /// 表示範囲の日数。いちばん遠い締め切りが入るように伸ばすが、短すぎ・長すぎにはしない。
    public static func rangeDays(latestDue: Date?, rangeStart: Date,
                                 minDays: Int = 28, maxDays: Int = 180) -> Int {
        guard let latestDue else { return minDays }
        let needed = Int((latestDue.timeIntervalSince(rangeStart) / day).rounded(.up)) + 2
        return min(max(needed, minDays), maxDays)
    }
}
