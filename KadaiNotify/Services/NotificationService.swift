import Foundation
import UserNotifications
import KadaiCore

/// iOS のローカル通知(iPhone の中だけで予約して鳴らす通知)を扱う。
enum NotificationService {
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
    static func reschedule(_ plans: [PlannedNotification], calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            switch plan.kind {
            case .individual(let taskID): content.threadIdentifier = "task-\(taskID)"
            case .nightly: content.threadIdentifier = "nightly"
            case .signingExpiry: content.threadIdentifier = "signing"
            }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
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
        content.body = "このように締め切りのお知らせが届きます。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                                                     content: content, trigger: trigger))
    }
}
