import Foundation
import UserNotifications
import KadaiCore

/// 「1 時間後にもう一度」で予約した再通知 1 件分
struct Snooze: Codable, Equatable {
    var taskID: String
    var title: String
    var body: String
    var fireDate: Date
}

/// 再通知の控え。通知は「全部消して作り直す」方式なので、再通知だけは別に覚えておいて毎回予約し直す
enum SnoozeStore {
    private static let key = "snoozes"

    static func load() -> [Snooze] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Snooze].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Snooze]) {
        AppGroup.defaults.set(try? JSONEncoder().encode(list), forKey: key)
    }

    /// まだ鳴っていなくて、提出物も未完了のままの再通知だけを残して返す(最大 5 件)
    static func active(now: Date, pendingIDs: Set<String>) -> [Snooze] {
        let list = Array(load().filter { $0.fireDate > now && pendingIDs.contains($0.taskID) }.suffix(5))
        save(list)
        return list
    }

    /// 同じ提出物の再通知は 1 件だけにする(押し直したら新しい時刻で上書き)
    static func add(_ snooze: Snooze) {
        save(load().filter { $0.taskID != snooze.taskID } + [snooze])
    }
}

/// iOS のローカル通知(iPhone の中だけで予約して鳴らす通知)を扱う。
enum NotificationService {
    /// 提出物の通知に付ける「種類の名前」。この名前の通知に「完了にする」「1 時間後にもう一度」のボタンが付く
    static let taskCategory = "TASK_REMINDER"
    static let doneAction = "TASK_DONE"
    static let snoozeAction = "TASK_SNOOZE_1H"
    /// 通知に埋め込む「どの提出物か」の目印の名前
    static let taskIDKey = "taskID"

    /// 通知を長押ししたときに出るボタンを iOS に登録する(アプリの起動時に 1 回呼ぶ)
    static func registerCategories() {
        // options が空 = アプリを前面に開かずに、裏で処理する
        let done = UNNotificationAction(identifier: doneAction, title: "完了にする", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "1 時間後にもう一度", options: [])
        let category = UNNotificationCategory(identifier: taskCategory, actions: [done, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    /// 予約済みの通知を全部消して、計算し直した通知を予約する。
    /// (iOS は 1 つのアプリにつき 64 件までしか予約できないので、NotificationPlanner が 64 件以内に絞る)
    static func reschedule(_ plans: [PlannedNotification], snoozes: [Snooze] = [], now: Date = .now,
                           calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            switch plan.kind {
            case .individual(let taskID), .start(let taskID):
                content.threadIdentifier = "task-\(taskID)"
                // ボタン(完了・再通知)を付け、どの提出物の通知かを覚えさせる
                content.categoryIdentifier = taskCategory
                content.userInfo = [taskIDKey: taskID]
            case .nightly: content.threadIdentifier = "nightly"
            case .morning: content.threadIdentifier = "morning"
            case .signingExpiry: content.threadIdentifier = "signing"
            }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        }
        // 「1 時間後にもう一度」の再通知を予約し直す
        for snooze in snoozes {
            let content = UNMutableNotificationContent()
            content.title = snooze.title
            content.body = snooze.body
            content.sound = .default
            content.threadIdentifier = "task-\(snooze.taskID)"
            content.categoryIdentifier = taskCategory
            content.userInfo = [taskIDKey: snooze.taskID]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, snooze.fireDate.timeIntervalSince(now)),
                                                            repeats: false)
            center.add(UNNotificationRequest(identifier: "\(NotificationPlanner.individualPrefix)\(snooze.taskID)-snooze",
                                             content: content, trigger: trigger))
        }
    }

    /// 完了・削除した課題の、通知センターに残っている通知を消す
    static func removeDelivered(forTaskKey key: String) {
        let prefix = NotificationPlanner.individualPrefix + key + "-"
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let ids = notifications.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// アプリアイコンの赤丸の数字
    static func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    /// 設定画面の「テスト通知」: 5 秒後に 1 回鳴らす
    static func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "テスト通知"
        content.body = "このように締め切りのお知らせが届きます。長押しすると「完了にする」「1 時間後にもう一度」のボタンが出ます(テストなので、押しても何も変わりません)。"
        content.sound = .default
        // 本物の通知と同じボタンを付ける。どの提出物でもない目印を入れておくので、押しても何も起きない
        content.categoryIdentifier = taskCategory
        content.userInfo = [taskIDKey: "test"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                                                     content: content, trigger: trigger))
    }
}
