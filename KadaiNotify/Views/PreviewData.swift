import Foundation
import SwiftData

/// サンプルデータ。Xcode の画面プレビューと、シミュレーターでの確認
/// (起動引数 -seedSampleData)だけで使う。普段のアプリでは入らない。
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = SharedStore.makeContainer(inMemory: true)!
        seed(into: container.mainContext)
        return container
    }()

    /// 起動引数に -seedSampleData があり、データが空のときだけサンプルを入れる
    static func seedIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"),
              ((try? context.fetchCount(FetchDescriptor<Assignment>())) ?? 0) == 0 else { return }
        seed(into: context)
        try? context.save()
    }

    static func seed(into context: ModelContext, now: Date = .now) {
        let info = Subject(name: "情報システム", colorHex: "#0090FF")
        let logic = Subject(name: "論理回路", colorHex: "#30A46C")
        let pd = Subject(name: "PD入門", colorHex: "#E5484D")
        [info, logic, pd].forEach { context.insert($0) }

        let samples: [(Subject, String, TimeInterval, Bool)] = [
            (info, "第7回レポート", -5 * 3600, false),
            (logic, "演習課題5", 4 * 3600, false),
            (pd, "振り返りシート", 26 * 3600, false),
            (info, "第8回レポート", 3 * 86400, false),
            (logic, "演習課題4", -2 * 86400, true),
        ]
        // テストのサンプル(「テスト」タブとウィジェットの確認用)
        let calendar = Calendar.current
        let exams: [(Subject, String, Int, String)] = [
            (logic, "小テスト 3", 2, "範囲は 7〜9 回"),
            (info, "期末試験", 12, "持ち込み不可"),
        ]
        for (subject, title, days, memo) in exams {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
            let exam = Exam(title: title, date: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day, memo: memo)
            context.insert(exam)
            exam.subject = subject
        }

        for (subject, title, offset, done) in samples {
            let assignment = Assignment(title: title, dueDate: now.addingTimeInterval(offset))
            context.insert(assignment)
            assignment.subject = subject
            assignment.isDone = done
            if done { assignment.completedAt = now }
        }
    }
}
