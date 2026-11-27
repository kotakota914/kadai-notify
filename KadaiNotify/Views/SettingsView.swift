import SwiftUI
import SwiftData
import UserNotifications
import KadaiCore

/// 設定画面
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var settings = AppSettings.load()
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ReminderRulesEditor(rules: $settings.globalRules)
                } header: {
                    Text("提出物ごとの通知(全体の設定)")
                } footer: {
                    Text("科目や提出物ごとに別の設定をしていなければ、この設定で通知します。左にスワイプでルールを削除。")
                }

                Section {
                    Toggle("毎晩のまとめ通知", isOn: $settings.nightlyEnabled)
                    if settings.nightlyEnabled {
                        DatePicker("時刻", selection: timeBinding(minutesOfDay: $settings.nightlyMinutes),
                                   displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("未完了の提出物が 1 件でもある限り、毎晩まとめて知らせます。同じ時刻の個別の通知はこの 1 通にまとめます。")
                }

                Section {
                    Toggle("朝のまとめ通知", isOn: $settings.morningEnabled)
                    if settings.morningEnabled {
                        DatePicker("時刻", selection: timeBinding(minutesOfDay: $settings.morningMinutes),
                                   displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("今日か明日が締め切りの提出物がある朝だけ、「今日締め切り ○ 件・明日 ○ 件」と知らせます。")
                }

                Section {
                    Toggle("テストの通知", isOn: $settings.examEnabled)
                } footer: {
                    Text("「テスト」タブに登録したテストの 7 日前・3 日前・前日に知らせます。時刻は毎晩のまとめ通知と同じです。")
                }

                Section {
                    Toggle("アイコンに未完了の件数を出す", isOn: $settings.badgeEnabled)
                    DatePicker("時刻がわからない締め切り", selection: timeBinding(minutesOfDay: $settings.defaultDueMinutes),
                               displayedComponents: .hourAndMinute)
                } footer: {
                    Text("取り込んだ提出物に時刻が書かれていないときは、この時刻を締め切りにします(初期値 8:50 = 1 限の前)。")
                }

                Section("通知の状態") {
                    LabeledContent("許可", value: authorizationText)
                    if authorization == .denied {
                        Button("iPhone の設定で通知を許可する") { openNotificationSettings() }
                    }
                    LabeledContent("予約中の通知", value: "\(pendingCount) / 64 件")
                    Button("テスト通知を送る(5 秒後)") { NotificationService.sendTest() }
                }

                Section {
                    Button(copied ? "コピーしました" : "Claude への頼み方をコピー") {
                        UIPasteboard.general.string = ImportParser.claudePrompt
                        copied = true
                    }
                } header: {
                    Text("学生ポータルからの取り込み")
                } footer: {
                    Text("Mac の Claude in Chrome にこの文を渡すと、「取り込み」に貼り付けられる形式で出力してくれます。")
                }

                Section("アプリの署名") {
                    if let expiry = SigningInfo.expirationDate {
                        LabeledContent("期限", value: DeadlineText.dateTime(expiry, calendar: .current))
                        Text("無料の Apple ID では 7 日ごとに Mac の Xcode から入れ直しが必要です。期限の前日の夜にお知らせします。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("期限を読み取れません(シミュレーターでは表示されません)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 提出物の画面の歯車ボタンから、下から出てくる画面(シート)として開くので、閉じるボタンを付ける
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await loadStatus() }
            .onChange(of: settings) { _, newValue in
                newValue.save()
                Refresher.refresh(context)
                Task {
                    // 通知の予約は iOS の中で少し遅れて終わるので、待ってから数える
                    try? await Task.sleep(for: .milliseconds(500))
                    await loadStatus()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadStatus() } }
            }
        }
    }

    private var authorizationText: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "許可済み"
        case .denied: return "許可されていません"
        case .notDetermined: return "まだ確認していません"
        @unknown default: return "不明"
        }
    }

    private func loadStatus() async {
        authorization = await NotificationService.authorizationStatus()
        pendingCount = await NotificationService.pendingCount()
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
