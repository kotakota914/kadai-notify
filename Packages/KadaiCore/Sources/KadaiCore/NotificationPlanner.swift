import Foundation

/// 通知の計算に必要な、課題 1 件分の情報(データベースから取り出した「写し」)。
public struct TaskSnapshot: Hashable, Sendable {
    public var id: String
    public var subject: String
    public var title: String
    public var due: Date
    /// この課題に使う通知ルール(課題 > 科目 > 全体 で決めたあとのもの)
    public var rules: [ReminderRule]

    public init(id: String, subject: String, title: String, due: Date, rules: [ReminderRule]) {
        self.id = id
        self.subject = subject
        self.title = title
        self.due = due
        self.rules = rules
    }
}

public struct PlannerSettings: Hashable, Sendable {
    /// 毎晩のまとめ通知を出すか
    public var nightlyEnabled: Bool = true
    public var nightlyHour: Int = 21
    public var nightlyMinute: Int = 0
    /// まとめ通知を何晩先まで予約するか
    public var nightsAhead: Int = 14
    /// 個別通知を最大何件予約するか(iOS の上限 64 件 = まとめ 14 + 個別 49 + 署名期限 1)
    public var maxIndividual: Int = 49
    /// まとめ通知の本文に並べる課題の最大数
    public var maxSummaryLines: Int = 4

    public init() {}
}

/// 予約する通知 1 件分
public struct PlannedNotification: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case individual(taskID: String)
        case nightly
        case signingExpiry
    }

    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var kind: Kind
}

/// 未完了の課題の一覧から、予約すべき通知(最大 64 件)を計算する。
/// 画面にも iOS の通知機能にも依存しないので、テストで中身を確かめられる。
public enum NotificationPlanner {
    public static let individualPrefix = "task-"
    public static let nightlyPrefix = "nightly-"
    public static let signingExpiryID = "signing-expiry"

    public static func plan(tasks: [TaskSnapshot],
                            settings: PlannerSettings,
                            signingExpiry: Date?,
                            now: Date,
                            calendar: Calendar) -> [PlannedNotification] {
        let sortedTasks = tasks.sorted { $0.due < $1.due }

        // 1. 毎晩のまとめ通知を鳴らす時刻(未完了が 1 件以上あるときだけ)
        let nights: [Date] = (settings.nightlyEnabled && !sortedTasks.isEmpty)
            ? nightlyTimes(settings: settings, now: now, calendar: calendar)
            : []
        let nightKeys = Set(nights.map(minuteKey))

        // 2. 個別通知の候補。まとめ通知と同じ分(minute)に鳴るものは、まとめ通知に含める
        var individual: [(task: TaskSnapshot, fire: Date)] = []
        var folded: [Int: Set<String>] = [:]   // まとめ通知の時刻 → 含める課題 ID
        for task in sortedTasks {
            var usedKeys = Set<Int>()
            for rule in task.rules {
                guard let fire = rule.fireDate(forDeadline: task.due, calendar: calendar),
                      fire > now, fire < task.due else { continue }
                let key = minuteKey(fire)
                guard usedKeys.insert(key).inserted else { continue }   // 同じ時刻のルールが 2 つあっても 1 回だけ
                if nightKeys.contains(key) {
                    folded[key, default: []].insert(task.id)
                } else {
                    individual.append((task, fire))
                }
            }
        }
        individual.sort { $0.fire < $1.fire }

        var result: [PlannedNotification] = individual.prefix(settings.maxIndividual).map { item in
            PlannedNotification(
                identifier: "\(individualPrefix)\(item.task.id)-\(minuteKey(item.fire))",
                fireDate: item.fire,
                title: taskTitle(item.task),
                body: "締め切り \(DeadlineText.dateTime(item.task.due, calendar: calendar))(\(DeadlineText.remaining(until: item.task.due, now: item.fire)))",
                kind: .individual(taskID: item.task.id))
        }

        // 3. 署名の期限切れのお知らせ(期限の前日、まとめ通知と同じ時刻)
        var expiryNightKey: Int?
        if let expiry = signingExpiry, expiry > now,
           let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: expiry)),
           let fire = calendar.date(bySettingHour: settings.nightlyHour, minute: settings.nightlyMinute, second: 0, of: dayBefore),
           fire > now {
            if nightKeys.contains(minuteKey(fire)) {
                expiryNightKey = minuteKey(fire)
            } else {
                result.append(PlannedNotification(
                    identifier: signingExpiryID,
                    fireDate: fire,
                    title: "アプリの署名期限が近づいています",
                    body: expiryMessage(expiry, calendar: calendar),
                    kind: .signingExpiry))
            }
        }

        // 4. 毎晩のまとめ通知
        for (index, night) in nights.enumerated() {
            let key = minuteKey(night)
            let highlighted = folded[key] ?? []
            let overdueCount = sortedTasks.filter { $0.due <= night }.count
            let title = overdueCount > 0
                ? "未完了の提出物 \(sortedTasks.count) 件(期限切れ \(overdueCount))"
                : "未完了の提出物 \(sortedTasks.count) 件"

            // 並び順: 期限切れ → 今夜知らせるべきもの(🔔) → その他。それぞれ締め切りが近い順
            func rank(_ t: TaskSnapshot) -> Int {
                if t.due <= night { return 0 }
                return highlighted.contains(t.id) ? 1 : 2
            }
            let ordered = sortedTasks.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map(\.element)

            var lines: [String] = []
            if expiryNightKey == key {
                lines.append("⚠️ " + expiryMessage(signingExpiry!, calendar: calendar))
            }
            for t in ordered.prefix(settings.maxSummaryLines) {
                let name = t.subject.isEmpty ? t.title : "\(t.subject) \(t.title)"
                if t.due <= night {
                    lines.append("⚠️ 期限切れ \(name)")
                } else {
                    let mark = highlighted.contains(t.id) ? "🔔" : "・"
                    lines.append("\(mark) \(DeadlineText.relativeDay(t.due, now: night, calendar: calendar)) \(name)")
                }
            }
            let rest = sortedTasks.count - min(sortedTasks.count, settings.maxSummaryLines)
            if rest > 0 { lines.append("ほか \(rest) 件") }
            if index == nights.count - 1 {
                lines.append("(通知の予約はここまで。アプリを開くと更新されます)")
            }

            result.append(PlannedNotification(
                identifier: nightlyPrefix + dayKey(night, calendar: calendar),
                fireDate: night,
                title: title,
                body: lines.joined(separator: "\n"),
                kind: .nightly))
        }

        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// これから先のまとめ通知の時刻(今日の分がまだなら今日から)
    static func nightlyTimes(settings: PlannerSettings, now: Date, calendar: Calendar) -> [Date] {
        var times: [Date] = []
        let today = calendar.startOfDay(for: now)
        var offset = 0
        while times.count < settings.nightsAhead && offset <= settings.nightsAhead + 1 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today),
               let t = calendar.date(bySettingHour: settings.nightlyHour, minute: settings.nightlyMinute, second: 0, of: day),
               t > now {
                times.append(t)
            }
            offset += 1
        }
        return times
    }

    static func taskTitle(_ task: TaskSnapshot) -> String {
        task.subject.isEmpty ? task.title : "【\(task.subject)】\(task.title)"
    }

    static func expiryMessage(_ expiry: Date, calendar: Calendar) -> String {
        "署名の期限は \(DeadlineText.dateTime(expiry, calendar: calendar)) です。Mac の Xcode から入れ直してください"
    }

    /// 「何分目か」を表す整数(同じ時刻かどうかの比較に使う)
    static func minuteKey(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
