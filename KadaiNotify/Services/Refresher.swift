import Foundation
import SwiftData
import WidgetKit
import KadaiCore

/// データが変わったとき・アプリを開いたときに呼ぶ「まとめて最新にする」処理。
/// 1. 繰り返し課題の新しい回を作る
/// 2. 通知を予約し直す
/// 3. アイコンのバッジとウィジェットを更新する
@MainActor
enum Refresher {
    static func refresh(_ context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        generateRecurring(context, now: now, calendar: calendar)
        try? context.save()

        let settings = AppSettings.load()
        let pending = fetchPending(context)
        let snapshots = pending.map { assignment in
            TaskSnapshot(id: assignment.key,
                         subject: assignment.subject?.name ?? "",
                         title: assignment.title,
                         due: assignment.dueDate,
                         rules: ReminderRule.resolve(task: assignment.reminderRules,
                                                     subject: assignment.subject?.reminderRules,
                                                     global: settings.globalRules))
        }
        let plans = NotificationPlanner.plan(tasks: snapshots,
                                             settings: settings.plannerSettings,
                                             signingExpiry: SigningInfo.expirationDate,
                                             now: now,
                                             calendar: calendar)
        NotificationService.reschedule(plans, calendar: calendar)
        NotificationService.setBadge(settings.badgeEnabled ? pending.count : 0)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func fetchPending(_ context: ModelContext) -> [Assignment] {
        let descriptor = FetchDescriptor<Assignment>(predicate: #Predicate { $0.isDone == false },
                                                     sortBy: [SortDescriptor(\.dueDate)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 有効な繰り返しのひな形から、14 日以内の新しい回を課題として作る
    static func generateRecurring(_ context: ModelContext, now: Date, calendar: Calendar) {
        let descriptor = FetchDescriptor<RecurringTemplate>(predicate: #Predicate { $0.isActive == true })
        let templates = (try? context.fetch(descriptor)) ?? []
        for template in templates {
            let occurrences = RecurrenceGenerator.occurrences(rule: template.weeklyRule,
                                                              lastGeneratedDue: template.lastGeneratedDue,
                                                              now: now, calendar: calendar)
            for occurrence in occurrences {
                // 同じ日の回がすでにある(日程を変える前に完了した回など)なら作らない
                if (template.assignments ?? []).contains(where: { calendar.isDate($0.dueDate, inSameDayAs: occurrence.due) }) {
                    template.lastGeneratedDue = occurrence.due
                    continue
                }
                let assignment = Assignment(title: occurrence.title, dueDate: occurrence.due, source: .recurring)
                context.insert(assignment)
                assignment.subject = template.subject
                assignment.template = template
                template.lastGeneratedDue = occurrence.due
            }
        }
    }
}

/// 科目を名前で探し、なければ作る
@MainActor
enum SubjectService {
    static func findOrCreate(name: String, in context: ModelContext) -> Subject? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        // 「情報 システム」と「情報システム」のような空白・大文字小文字の違いは同じ科目とみなす
        if let found = all.first(where: { ImportMatcher.key($0.name) == ImportMatcher.key(trimmed) }) { return found }
        let subject = Subject(name: trimmed, colorHex: SubjectPalette.nextColor(used: all.map(\.colorHex)))
        context.insert(subject)
        return subject
    }
}

/// アプリの署名の期限(無料の Apple ID だと入れてから 7 日)
enum SigningInfo {
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }   // シミュレーターでは nil
        return ProvisioningProfile.expirationDate(fromProfileData: data)
    }()
}
