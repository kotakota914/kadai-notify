import SwiftUI
import SwiftData
import UserNotifications

/// アプリの入口。@main が付いた型から iOS がアプリを起動する。
@main
struct KadaiNotifyApp: App {
    // 通知まわりの細かい設定のために、昔ながらの AppDelegate もつなぐ
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer? = SharedStore.makeContainer()

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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// アプリを開いている最中に通知が来たときも、画面上部にバナーを出す
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// 下のタブで 3 つの画面を切り替える
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            AssignmentListView()
                .tabItem { Label("提出物", systemImage: "checklist") }
            SubjectListView()
                .tabItem { Label("科目・繰り返し", systemImage: "books.vertical") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .task {
            // シミュレーターでの確認用(scripts/run-simulator.sh --sample)
            PreviewData.seedIfRequested(context)
            // 初回だけ「通知を許可しますか?」が出る
            await NotificationService.requestAuthorizationIfNeeded()
            Refresher.refresh(context)
        }
        .onChange(of: scenePhase) { _, phase in
            // アプリを開くたびに、繰り返し課題の追加と通知の予約し直しを行う
            if phase == .active { Refresher.refresh(context) }
        }
    }
}
