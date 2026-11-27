import Foundation

/// 通知の計算に必要な、課題 1 件分の情報(データベースから取り出した「写し」)。
public struct TaskSnapshot: Hashable, Sendable {
    public var id: String
    public var subject: String
    public var title: String
    public var due: Date
    /// この課題に使う通知ルール(課題 > 科目 > 全体 で決めたあとのもの)
    public var rules: [ReminderRule]
    /// 着手日(取りかかり始める予定の日時)。決めていなければ nil
    public var start: Date?

    public init(id: String, subject: String, title: String, due: Date, rules: [ReminderRule], start: Date? = nil) {
        self.id = id
        self.subject = subject
        self.title = title
        self.due = due
        self.rules = rules
        self.start = start
    }
}

public struct PlannerSettings: Hashable, Sendable {
    /// 毎晩のまとめ通知を出すか
    public var nightlyEnabled: Bool = true
    public var nightlyHour: Int = 21
    public var nightlyMinute: Int = 0
    /// まとめ通知を何晩先まで予約するか
    public var nightsAhead: Int = 14
    /// 朝のまとめ通知(「今日締め切り ○ 件・明日 ○ 件」)を出すか
    public var morningEnabled: Bool = false
    public var morningHour: Int = 7
    public var morningMinute: Int = 30
    /// 朝のまとめ通知を何日先まで予約するか
    public var morningsAhead: Int = 7
    /// 個別通知(締め切り前の通知と着手日の通知)を最大何件予約するか。
    /// iOS の上限 64 件 = 夜のまとめ 14 + 個別 49 + 署名期限 1。朝のまとめを出す分だけ、個別の枠を減らす
    public var maxIndividual: Int = 49
    /// ほかの用途(「1 時間後にもう一度」の再通知など)のために空けておく件数。個別の枠から引く
    public var reservedSlots: Int = 0
    /// まとめ通知の本文に並べる課題の最大数
    public var maxSummaryLines: Int = 4

    public init() {}
}

/// 予約する通知 1 件分
public struct PlannedNotification: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case individual(taskID: String)
        /// 着手日の通知
        case start(taskID: String)
        case nightly
        /// 朝のまとめ通知
        case morning
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
    public static let morningPrefix = "morning-"
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
        var individual: [(task: TaskSnapshot, fire: Date, isStart: Bool)] = []
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
                    individual.append((task, fire, false))
                }
            }
            // 着手日の通知(これから来る着手日で、締め切りより前のものだけ)
            if let start = task.start, start > now, start < task.due {
                individual.append((task, start, true))
            }
        }
        individual.sort { $0.fire < $1.fire }

        // 朝のまとめ通知(今日か明日が締め切りの提出物がある朝だけ)
        let morningPlans = settings.morningEnabled
            ? morningDigests(tasks: sortedTasks, settings: settings, now: now, calendar: calendar)
            : []

        // 個別通知の枠。朝のまとめと、空けておく件数の分だけ減らす(合計が 64 件を超えないように)
        let individualLimit = max(0, settings.maxIndividual - morningPlans.count - settings.reservedSlots)
        var result: [PlannedNotification] = individual.prefix(individualLimit).map { item in
            let deadline = "締め切り \(DeadlineText.dateTime(item.task.due, calendar: calendar))(\(DeadlineText.remaining(until: item.task.due, now: item.fire)))"
            if item.isStart {
                return PlannedNotification(
                    identifier: "\(individualPrefix)\(item.task.id)-start",
                    fireDate: item.fire,
                    title: taskTitle(item.task),
                    body: "そろそろ取りかかる予定の日時です。\(deadline)",
                    kind: .start(taskID: item.task.id))
            }
            return PlannedNotification(
                identifier: "\(individualPrefix)\(item.task.id)-\(minuteKey(item.fire))",
                fireDate: item.fire,
                title: taskTitle(item.task),
                body: deadline,
                kind: .individual(taskID: item.task.id))
        }
        result.append(contentsOf: morningPlans)

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
        dailyTimes(hour: settings.nightlyHour, minute: settings.nightlyMinute,
                   count: settings.nightsAhead, now: now, calendar: calendar)
    }

    /// 毎日の決まった時刻を、これから先の count 回分だけ並べる(今日の分がまだなら今日から)
    static func dailyTimes(hour: Int, minute: Int, count: Int, now: Date, calendar: Calendar) -> [Date] {
        var times: [Date] = []
        let today = calendar.startOfDay(for: now)
        var offset = 0
        while times.count < count && offset <= count + 1 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today),
               let t = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               t > now {
                times.append(t)
            }
            offset += 1
        }
        return times
    }

    /// 朝のまとめ通知。その日か翌日が締め切りの提出物がある朝だけ作る。
    /// 例: タイトル「今日締め切り 2 件・明日 1 件」、本文は締め切りが近い順に最大 4 件
    static func morningDigests(tasks sortedTasks: [TaskSnapshot], settings: PlannerSettings,
                               now: Date, calendar: Calendar) -> [PlannedNotification] {
        let mornings = dailyTimes(hour: settings.morningHour, minute: settings.morningMinute,
                                  count: settings.morningsAhead, now: now, calendar: calendar)
        var result: [PlannedNotification] = []
        for morning in mornings {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: morning) else { continue }
            // 今日の分は、この朝より後に締め切りが来るものだけ(すでに過ぎたものは期限切れに数える)
            let today = sortedTasks.filter { $0.due > morning && calendar.isDate($0.due, inSameDayAs: morning) }
            let tomorrow = sortedTasks.filter { calendar.isDate($0.due, inSameDayAs: nextDay) }
            if today.isEmpty && tomorrow.isEmpty { continue }
            let overdueCount = sortedTasks.filter { $0.due <= morning }.count

            var title = "今日締め切り \(today.count) 件・明日 \(tomorrow.count) 件"
            if overdueCount > 0 { title += "(期限切れ \(overdueCount))" }

            let listed = today + tomorrow
            var lines = listed.prefix(settings.maxSummaryLines).map { t -> String in
                let name = t.subject.isEmpty ? t.title : "\(t.subject) \(t.title)"
                return "・ \(DeadlineText.relativeDay(t.due, now: morning, calendar: calendar)) \(name)"
            }
            let rest = listed.count - min(listed.count, settings.maxSummaryLines)
            if rest > 0 { lines.append("ほか \(rest) 件") }

            result.append(PlannedNotification(
                identifier: morningPrefix + dayKey(morning, calendar: calendar),
                fireDate: morning,
                title: title,
                body: lines.joined(separator: "\n"),
                kind: .morning))
        }
        return result
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
