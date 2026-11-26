import XCTest
@testable import KadaiCore

final class NotificationPlannerTests: XCTestCase {
    let now = at(2026, 11, 26, 12, 0)   // 木曜 12:00

    func report(rules: [ReminderRule] = ReminderRule.defaultRules,
                due: Date = at(2026, 12, 3, 17, 0), id: String = "A") -> TaskSnapshot {
        TaskSnapshot(id: id, subject: "情報システム", title: "第8回レポート", due: due, rules: rules)
    }

    func plan(_ tasks: [TaskSnapshot], nightly: Bool = true, expiry: Date? = nil,
              now: Date? = nil) -> [PlannedNotification] {
        var settings = PlannerSettings()
        settings.nightlyEnabled = nightly
        return NotificationPlanner.plan(tasks: tasks, settings: settings, signingExpiry: expiry,
                                        now: now ?? self.now, calendar: tokyo)
    }

    func nightly(_ plans: [PlannedNotification], on date: Date) -> PlannedNotification? {
        plans.first { $0.kind == .nightly && $0.fireDate == date }
    }

    // 受け入れ条件 F-04: 木曜 17:00 締め切り → 月曜 21:00 と水曜 21:00 に知らせが来る
    func testDefaultRulesWithoutNightlyFireOnMondayAndWednesdayNight() {
        let plans = plan([report()], nightly: false)
        XCTAssertEqual(plans.map(\.fireDate), [at(2026, 11, 30, 21, 0), at(2026, 12, 2, 21, 0)])
        XCTAssertEqual(plans[0].title, "【情報システム】第8回レポート")
        XCTAssertEqual(plans[0].body, "締め切り 12/3(木) 17:00(あと 2 日)")
        XCTAssertEqual(plans[1].body, "締め切り 12/3(木) 17:00(あと 20 時間)")
    }

    // 同じ 21:00 のまとめ通知があるときは、個別通知はまとめ通知の中に入る(1 通にまとめる)
    func testIndividualAtNightlyTimeIsFoldedIntoSummary() {
        let plans = plan([report()])
        XCTAssertEqual(plans.filter { $0.kind == .nightly }.count, 14)
        XCTAssertTrue(plans.allSatisfy { $0.kind == .nightly })

        let monday = nightly(plans, on: at(2026, 11, 30, 21, 0))
        XCTAssertEqual(monday?.title, "未完了の提出物 1 件")
        XCTAssertEqual(monday?.body, "🔔 12/3(木) 17:00 情報システム 第8回レポート")

        let friday = nightly(plans, on: at(2026, 11, 27, 21, 0))
        XCTAssertEqual(friday?.body, "・ 12/3(木) 17:00 情報システム 第8回レポート")

        let wednesday = nightly(plans, on: at(2026, 12, 2, 21, 0))
        XCTAssertEqual(wednesday?.body, "🔔 明日 17:00 情報システム 第8回レポート")
    }

    // F-05: 期限を過ぎても完了するまで毎晩含める
    func testOverdueTaskStaysInNightlySummary() {
        let plans = plan([report()])
        let afterDue = nightly(plans, on: at(2026, 12, 4, 21, 0))
        XCTAssertEqual(afterDue?.title, "未完了の提出物 1 件(期限切れ 1)")
        XCTAssertEqual(afterDue?.body, "⚠️ 期限切れ 情報システム 第8回レポート")
    }

    func testNightlyStartsTonightAndLastOneSaysToOpenApp() {
        let plans = plan([report()])
        XCTAssertEqual(plans.first?.fireDate, at(2026, 11, 26, 21, 0))
        XCTAssertEqual(plans.last?.fireDate, at(2026, 12, 9, 21, 0))
        XCTAssertTrue(plans.last?.body.contains("アプリを開くと更新されます") ?? false)

        let lateNight = plan([report()], now: at(2026, 11, 26, 22, 0))
        XCTAssertEqual(lateNight.first?.fireDate, at(2026, 11, 27, 21, 0))
    }

    func testNoTasksMeansNoNotifications() {
        XCTAssertTrue(plan([]).isEmpty)
    }

    func testHoursBeforeIsNotFolded() {
        let plans = plan([report(rules: [.hoursBefore(3)])])
        let individual = plans.filter { $0.kind == .individual(taskID: "A") }
        XCTAssertEqual(individual.map(\.fireDate), [at(2026, 12, 3, 14, 0)])
    }

    func testPastAndAfterDeadlineRulesAreSkipped() {
        // 締め切りの 2 日前に登録 → 「3 日前」はもう過ぎているので鳴らさない
        let plans = plan([report()], nightly: false, now: at(2026, 12, 1, 12, 0))
        XCTAssertEqual(plans.map(\.fireDate), [at(2026, 12, 2, 21, 0)])

        // 「当日の 21:00」は 17:00 締め切りより後なので鳴らさない
        XCTAssertTrue(plan([report(rules: [.daysBefore(0)])], nightly: false).isEmpty)
    }

    func testSummaryShowsAtMostFourLinesThenRest() {
        let tasks = (0..<6).map { i in
            TaskSnapshot(id: "T\(i)", subject: "科目\(i)", title: "課題\(i)",
                         due: at(2026, 12, 10 + i, 17, 0), rules: [])
        }
        let first = nightly(plan(tasks), on: at(2026, 11, 26, 21, 0))
        let lines = first?.body.split(separator: "\n") ?? []
        XCTAssertEqual(first?.title, "未完了の提出物 6 件")
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines.last, "ほか 2 件")
    }

    func testNeverExceedsSixtyFourAndIdentifiersAreUnique() {
        let tasks = (0..<100).map { i in
            TaskSnapshot(id: "T\(i)", subject: "S", title: "課題\(i)",
                         due: now.addingTimeInterval(Double(i + 2) * 3600),
                         rules: [.hoursBefore(1)])
        }
        let plans = plan(tasks, expiry: at(2026, 12, 1, 14, 20))
        XCTAssertLessThanOrEqual(plans.count, 64)
        XCTAssertEqual(plans.filter { if case .individual = $0.kind { return true } else { return false } }.count, 49)
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
    }

    // F-12: 署名期限の前日 21:00 にお知らせ。課題がなければ単独の通知
    func testSigningExpiryAloneWhenNoTasks() {
        let plans = plan([], expiry: at(2026, 12, 1, 14, 20))
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].kind, .signingExpiry)
        XCTAssertEqual(plans[0].fireDate, at(2026, 11, 30, 21, 0))
        XCTAssertTrue(plans[0].body.contains("12/1(火) 14:20"))
    }

    // まとめ通知がある夜なら、その先頭行に入る
    func testSigningExpiryFoldedIntoNightly() {
        let plans = plan([report()], expiry: at(2026, 12, 1, 14, 20))
        XCTAssertFalse(plans.contains { $0.kind == .signingExpiry })
        let monday = nightly(plans, on: at(2026, 11, 30, 21, 0))
        XCTAssertTrue(monday?.body.hasPrefix("⚠️ 署名の期限は 12/1(火) 14:20") ?? false)
    }
}
