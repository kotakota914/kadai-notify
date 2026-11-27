import Foundation
import SwiftData

/// アプリとウィジェットでデータを共有するための「App Group」(同じ開発者のアプリどうしの共有フォルダ)。
/// バンドル ID を変えたときは、ここと Config/*.entitlements の両方を同じ名前に変えること。
enum AppGroup {
    static let identifier = "group.io.github.kotakota914.KadaiNotify"

    /// 設定の保存場所(App Group が使えなければ普通の保存場所)
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// SwiftData のデータベースを開く
enum SharedStore {
    static let schema = Schema([Assignment.self, Subject.self, RecurringTemplate.self, Exam.self])

    /// データベースを開く。開けなければ nil
    static func makeContainer(inMemory: Bool = false) -> ModelContainer? {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            // App Group の共有フォルダに保存 → ウィジェットからも読める
            configuration = ModelConfiguration(schema: schema,
                                               url: folder.appendingPathComponent("KadaiNotify.store"),
                                               cloudKitDatabase: .none)
        } else {
            // App Group が使えない場合(署名の設定が足りないなど)はアプリ専用の場所に保存
            configuration = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        }
        return try? ModelContainer(for: schema, configurations: [configuration])
    }
}
