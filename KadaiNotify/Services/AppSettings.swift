import Foundation
import KadaiCore

/// 設定画面の内容。UserDefaults(小さな設定を保存する場所)に入れておく。
struct AppSettings: Equatable {
    /// 全体の通知ルール(初期値: 3 日前・1 日前の 21:00)
    var globalRules: [ReminderRule] = ReminderRule.defaultRules
    /// 毎晩のまとめ通知
    var nightlyEnabled: Bool = true
    /// まとめ通知の時刻(0:00 からの分。21:00 = 1260)
    var nightlyMinutes: Int = 21 * 60
    /// 朝のまとめ通知(今日・明日が締め切りの提出物がある朝だけ)
    var morningEnabled: Bool = true
    /// 朝のまとめ通知の時刻(0:00 からの分。7:30 = 450)
    var morningMinutes: Int = 7 * 60 + 30
    /// テストの通知(7 日前・3 日前・前日の夜)
    var examEnabled: Bool = true
    /// アイコンのバッジ
    var badgeEnabled: Bool = true
    /// 時刻がわからない締め切りの時刻(8:50 = 530)
    var defaultDueMinutes: Int = 8 * 60 + 50

    private enum Key {
        static let globalRules = "globalReminderRules"
        static let nightlyEnabled = "nightlyEnabled"
        static let nightlyMinutes = "nightlyMinutes"
        static let morningEnabled = "morningEnabled"
        static let morningMinutes = "morningMinutes"
        static let examEnabled = "examEnabled"
        static let badgeEnabled = "badgeEnabled"
        static let defaultDueMinutes = "defaultDueMinutes"
    }

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> AppSettings {
        var settings = AppSettings()
        if let rules = ReminderRule.decodeList(defaults.data(forKey: Key.globalRules)) {
            settings.globalRules = rules
        }
        if defaults.object(forKey: Key.nightlyEnabled) != nil {
            settings.nightlyEnabled = defaults.bool(forKey: Key.nightlyEnabled)
        }
        if defaults.object(forKey: Key.nightlyMinutes) != nil {
            settings.nightlyMinutes = defaults.integer(forKey: Key.nightlyMinutes)
        }
        if defaults.object(forKey: Key.morningEnabled) != nil {
            settings.morningEnabled = defaults.bool(forKey: Key.morningEnabled)
        }
        if defaults.object(forKey: Key.morningMinutes) != nil {
            settings.morningMinutes = defaults.integer(forKey: Key.morningMinutes)
        }
        if defaults.object(forKey: Key.examEnabled) != nil {
            settings.examEnabled = defaults.bool(forKey: Key.examEnabled)
        }
        if defaults.object(forKey: Key.badgeEnabled) != nil {
            settings.badgeEnabled = defaults.bool(forKey: Key.badgeEnabled)
        }
        if defaults.object(forKey: Key.defaultDueMinutes) != nil {
            settings.defaultDueMinutes = defaults.integer(forKey: Key.defaultDueMinutes)
        }
        return settings
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(ReminderRule.encodeList(globalRules), forKey: Key.globalRules)
        defaults.set(nightlyEnabled, forKey: Key.nightlyEnabled)
        defaults.set(nightlyMinutes, forKey: Key.nightlyMinutes)
        defaults.set(morningEnabled, forKey: Key.morningEnabled)
        defaults.set(morningMinutes, forKey: Key.morningMinutes)
        defaults.set(examEnabled, forKey: Key.examEnabled)
        defaults.set(badgeEnabled, forKey: Key.badgeEnabled)
        defaults.set(defaultDueMinutes, forKey: Key.defaultDueMinutes)
    }

    /// 通知の計算に渡す形にする
    var plannerSettings: PlannerSettings {
        var settings = PlannerSettings()
        settings.nightlyEnabled = nightlyEnabled
        settings.nightlyHour = nightlyMinutes / 60
        settings.nightlyMinute = nightlyMinutes % 60
        settings.morningEnabled = morningEnabled
        settings.morningHour = morningMinutes / 60
        settings.morningMinute = morningMinutes % 60
        settings.examEnabled = examEnabled
        return settings
    }

    /// 新しく課題を追加するときの締め切りの初期値: 7 日後の初期時刻
    func defaultNewDueDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: defaultDueMinutes / 60, minute: defaultDueMinutes % 60,
                             second: 0, of: day) ?? day
    }
}
