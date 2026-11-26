import Foundation

/// 締め切りの日時や残り時間を、画面や通知に出す日本語の文字にする。
public enum DeadlineText {
    /// Calendar の weekday(1 = 日曜 … 7 = 土曜)に対応する曜日
    public static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    public static func weekdaySymbol(_ weekday: Int) -> String {
        weekdaySymbols[((weekday - 1) % 7 + 7) % 7]
    }

    /// 例: 「12/3(水) 17:00」
    public static func dateTime(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: date)
        let minute = String(format: "%02d", c.minute ?? 0)
        return "\(c.month ?? 0)/\(c.day ?? 0)(\(weekdaySymbol(c.weekday ?? 1))) \(c.hour ?? 0):\(minute)"
    }

    /// 例: 「12/3(水)」
    public static func date(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)(\(weekdaySymbol(c.weekday ?? 1)))"
    }

    /// 例: 「17:00」
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 今日・明日なら「今日 17:00」「明日 17:00」、それ以外は「12/5(金) 8:50」
    public static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 99
        switch diff {
        case 0: return "今日 " + time(date, calendar: calendar)
        case 1: return "明日 " + time(date, calendar: calendar)
        default: return dateTime(date, calendar: calendar)
        }
    }

    /// 残り時間。例: 「あと 2 日」「あと 1 日 5 時間」「あと 3 時間」「あと 25 分」「まもなく」「5 時間超過」
    public static func remaining(until due: Date, now: Date) -> String {
        let seconds = due.timeIntervalSince(now)
        let overdue = seconds < 0
        let totalMinutes = Int(abs(seconds) / 60)
        let hours = totalMinutes / 60
        let days = hours / 24

        if overdue {
            if totalMinutes < 60 { return "\(max(totalMinutes, 1)) 分超過" }
            if hours < 24 { return "\(hours) 時間超過" }
            return "\(days) 日超過"
        }
        if totalMinutes < 1 { return "まもなく" }
        if totalMinutes < 60 { return "あと \(totalMinutes) 分" }
        if hours < 24 { return "あと \(hours) 時間" }
        if days < 2 {
            let restHours = hours % 24
            return restHours == 0 ? "あと 1 日" : "あと 1 日 \(restHours) 時間"
        }
        return "あと \(days) 日"
    }
}

/// 一覧画面での分け方
public enum DueGroup: Int, CaseIterable, Comparable, Sendable {
    case overdue, today, tomorrow, later

    public var title: String {
        switch self {
        case .overdue: return "期限切れ"
        case .today: return "今日"
        case .tomorrow: return "明日"
        case .later: return "それ以降"
        }
    }

    public static func < (lhs: DueGroup, rhs: DueGroup) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func group(for due: Date, now: Date, calendar: Calendar) -> DueGroup {
        if due <= now { return .overdue }
        if calendar.isDate(due, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(due, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        return .later
    }
}
