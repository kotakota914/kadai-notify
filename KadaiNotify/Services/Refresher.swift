import Foundation
import SwiftUI
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
                                                     global: settings.globalRules),
                         start: assignment.startDate)
        }
        // 「1 時間後にもう一度」で予約した再通知のうち、まだ鳴っていないもの。その件数分だけ通知の枠を空ける
        let snoozes = SnoozeStore.active(now: now, pendingIDs: Set(pending.map(\.key)))
        var plannerSettings = settings.plannerSettings
        plannerSettings.reservedSlots = snoozes.count
        // これから来るテスト(終わったテストは通知しない)
        let exams = ((try? context.fetch(FetchDescriptor<Exam>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.date > now }
            .map { ExamSnapshot(id: $0.key, subject: $0.subject?.name ?? "", title: $0.title, date: $0.date) }
        let plans = NotificationPlanner.plan(tasks: snapshots,
                                             exams: exams,
                                             settings: plannerSettings,
                                             signingExpiry: SigningInfo.expirationDate,
                                             now: now,
                                             calendar: calendar)
        NotificationService.reschedule(plans, snoozes: snoozes, now: now, calendar: calendar)
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

/// 提出物に対する操作のうち、複数の画面(一覧・カレンダー)から使うもの
@MainActor
enum AssignmentActions {
    /// 完了 ⇔ 未完了を切り替え、通知・バッジ・ウィジェットを更新する
    static func toggleDone(_ assignment: Assignment, in context: ModelContext) {
        withAnimation {
            assignment.isDone.toggle()
            assignment.completedAt = assignment.isDone ? .now : nil
        }
        if assignment.isDone {
            NotificationService.removeDelivered(forTaskKey: assignment.key)
        }
        try? context.save()
        Refresher.refresh(context)
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
