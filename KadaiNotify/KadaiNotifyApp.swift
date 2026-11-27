import SwiftUI
import SwiftData
import UserNotifications

/// アプリの入口。@main が付いた型から iOS がアプリを起動する。
@main
struct KadaiNotifyApp: App {
    // 通知まわりの細かい設定のために、昔ながらの AppDelegate もつなぐ
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer? = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
            } else {
                ContentUnavailableView("データを開けませんでした",
                                       systemImage: "externaldrive.badge.xmark",
                                       description: Text("アプリを入れ直しても直らない場合は、Xcode のログを確認してください。"))
            }
        }
    }
}

/// アプリ全体で 1 つだけ開くデータベース。画面と、通知のボタンの処理の両方から使う
enum AppContainer {
    static let shared: ModelContainer? = SharedStore.makeContainer()
}

/// 通知のボタン(「完了にする」「1 時間後にもう一度」)が押されたときの処理
@MainActor
enum NotificationActions {
    static func handle(action: String, taskID: String, title: String, body: String, now: Date = .now) {
        guard let context = AppContainer.shared?.mainContext else { return }
        switch action {
        case NotificationService.doneAction:
            // その提出物を完了にする(通知センターに残っている通知も消える)
            guard let assignment = Refresher.fetchPending(context).first(where: { $0.key == taskID }) else { return }
            assignment.isDone = true
            assignment.completedAt = now
            NotificationService.removeDelivered(forTaskKey: taskID)
            try? context.save()
            Refresher.refresh(context, now: now)
        case NotificationService.snoozeAction:
            // 1 時間後に、同じ内容の通知をもう一度出す
            SnoozeStore.add(Snooze(taskID: taskID, title: title, body: body, fireDate: now.addingTimeInterval(3600)))
            Refresher.refresh(context, now: now)
        default:
            break   // 通知そのものを押してアプリを開いただけのときは、何もしない
        }
    }

    /// 動作確認用。起動引数 `-debugNotificationAction <ボタンの名前> <提出物の ID>` を付けて起動すると、
    /// 通知のボタンが押されたときと同じ処理を動かす。開発版(Debug)にだけ入る
    static func runDebugActionIfRequested() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-debugNotificationAction"), args.count > index + 2 else { return }
        handle(action: args[index + 1], taskID: args[index + 2],
               title: "【動作確認】再通知", body: "1 時間後にもう一度のテスト")
        #endif
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()
        return true
    }

    /// アプリを開いている最中に通知が来たときも、画面上部にバナーを出す
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 通知のボタンが押されたとき(アプリが閉じていても、裏で呼ばれる)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let taskID = content.userInfo[NotificationService.taskIDKey] as? String
        let action = response.actionIdentifier
        let title = content.title
        let body = content.body
        Task { @MainActor in
            if let taskID {
                NotificationActions.handle(action: action, taskID: taskID, title: title, body: body)
            }
            completionHandler()
        }
    }
}

/// 下のタブで 4 つの画面(提出物・カレンダー・ガント・科目)を切り替える
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// Mac から送られてきた取り込みテキスト。入っている間、取り込みの確認画面を出す
    @State private var inbox: InboxText?
    /// いま確認画面に見せているテキスト(閉じたときに、新しいファイルが届いていないか見分けるため)
    @State private var shownInboxText: String?

    /// `.sheet(item:)` に渡すための入れ物(Identifiable = 1 件ずつ区別できる型)
    private struct InboxText: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        TabView {
            AssignmentListView()
                .tabItem { Label("提出物", systemImage: "checklist") }
            CalendarTabView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
            GanttTabView()
                .tabItem { Label("ガント", systemImage: "chart.bar.xaxis") }
            SubjectListView()
                .tabItem { Label("科目・繰り返し", systemImage: "books.vertical") }
            // 設定はタブに置かず、「提出物」の右上の歯車ボタンから開く
        }
        .task {
            // シミュレーターでの確認用(scripts/run-simulator.sh --sample)
            PreviewData.seedIfRequested(context)
            // シミュレーターでの確認用: 通知のボタンが押されたことにして処理を動かす
            NotificationActions.runDebugActionIfRequested()
            // 初回だけ「通知を許可しますか?」が出る
            await NotificationService.requestAuthorizationIfNeeded()
            Refresher.refresh(context)
            checkInbox()
        }
        .onChange(of: scenePhase) { _, phase in
            // アプリを開くたびに、繰り返し課題の追加と通知の予約し直しを行う
            if phase == .active {
                Refresher.refresh(context)
                checkInbox()
            }
        }
        .sheet(item: $inbox, onDismiss: inboxDismissed) { inbox in
            ImportView(initialText: inbox.text)
        }
    }

    /// Mac から送られてきたファイルがあれば、取り込みの確認画面を出す
    private func checkInbox() {
        // すでに確認画面を出している間は読み直さない(直している途中の内容が消えないように)
        guard inbox == nil, let text = ImportInbox.read() else { return }
        shownInboxText = text
        inbox = InboxText(text: text)
    }

    /// 確認画面を閉じたとき(登録してもキャンセルしても)に呼ばれる
    private func inboxDismissed() {
        // 受け取り箱の中身が、いま見せていたものと同じときだけ空にする。
        // 画面を開いている間に Mac から新しいファイルが届いていたら、それは消さずに続けて見せる
        if ImportInbox.read() == shownInboxText {
            ImportInbox.clear()
        }
        shownInboxText = nil
        checkInbox()
    }
}
