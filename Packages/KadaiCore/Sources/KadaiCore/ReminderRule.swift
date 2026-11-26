import Foundation

/// 通知を「いつ鳴らすか」を表すルール 1 つ分。
/// 例: 「3 日前の 21:00」「3 時間前」
public struct ReminderRule: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// N 日前の HH:MM(N = 0 なら締め切り当日の HH:MM)
        case daysBefore
        /// 締め切りの N 時間前
        case hoursBefore
    }

    public var id: UUID
    public var kind: Kind
    /// N(何日前 / 何時間前)
    public var amount: Int
    /// daysBefore のときに鳴らす時刻
    public var hour: Int
    public var minute: Int

    public init(id: UUID = UUID(), kind: Kind, amount: Int, hour: Int = 21, minute: Int = 0) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.hour = hour
        self.minute = minute
    }

    public static func daysBefore(_ days: Int, hour: Int = 21, minute: Int = 0) -> ReminderRule {
        ReminderRule(kind: .daysBefore, amount: days, hour: hour, minute: minute)
    }

    public static func hoursBefore(_ hours: Int) -> ReminderRule {
        ReminderRule(kind: .hoursBefore, amount: hours)
    }

    /// 全体設定の初期値: 3 日前の 21:00 と 1 日前の 21:00
    public static var defaultRules: [ReminderRule] {
        [.daysBefore(3), .daysBefore(1)]
    }

    /// 締め切り日時から、このルールで通知を鳴らす日時を計算する。
    public func fireDate(forDeadline due: Date, calendar: Calendar) -> Date? {
        switch kind {
        case .daysBefore:
            let dueDay = calendar.startOfDay(for: due)
            guard let day = calendar.date(byAdding: .day, value: -amount, to: dueDay) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        case .hoursBefore:
            return due.addingTimeInterval(TimeInterval(-amount * 3600))
        }
    }

    /// 画面に出す説明。例: 「3 日前の 21:00」「当日の 8:00」「3 時間前」
    public var label: String {
        switch kind {
        case .daysBefore:
            let time = String(format: "%d:%02d", hour, minute)
            return amount == 0 ? "当日の \(time)" : "\(amount) 日前の \(time)"
        case .hoursBefore:
            return "\(amount) 時間前"
        }
    }

    /// 通知ルールを「課題 > 科目 > 全体」の順で決める。
    /// nil は「指定なし(下の設定を使う)」、空の配列は「通知しない」という意味。
    public static func resolve(task: [ReminderRule]?, subject: [ReminderRule]?, global: [ReminderRule]) -> [ReminderRule] {
        task ?? subject ?? global
    }

    /// 複数のルールの説明をつなげる。空なら「通知しない」。
    public static func summary(_ rules: [ReminderRule]) -> String {
        rules.isEmpty ? "通知しない" : rules.map(\.label).joined(separator: "、")
    }

    // MARK: - 保存用(JSON に変換して保存する)

    public static func encodeList(_ rules: [ReminderRule]) -> Data {
        (try? JSONEncoder().encode(rules)) ?? Data()
    }

    public static func decodeList(_ data: Data?) -> [ReminderRule]? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([ReminderRule].self, from: data)
    }
}
