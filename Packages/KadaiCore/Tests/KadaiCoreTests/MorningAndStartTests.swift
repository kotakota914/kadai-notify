import XCTest
@testable import KadaiCore

/// 朝のまとめ通知と、着手日の通知のテスト
final class MorningAndStartTests: XCTestCase {
    let now = at(2026, 11, 26, 12, 0)   // 木曜 12:00

    func task(_ id: String, due: Date, rules: [ReminderRule] = [], start: Date? = nil) -> TaskSnapshot {
        TaskSnapshot(id: id, subject: "情報システム", title: "課題\(id)", due: due, rules: rules, start: start)
    }

    func plan(_ tasks: [TaskSnapshot], configure: (inout PlannerSettings) -> Void = { _ in }) -> [PlannedNotification] {
        var settings = PlannerSettings()
        settings.nightlyEnabled = false
        configure(&settings)
        return NotificationPlanner.plan(tasks: tasks, settings: settings, signingExpiry: nil, now: now, calendar: tokyo)
    }

    // MARK: 朝のまとめ通知

    func testMorningDigestIsOffByDefault() {
        let plans = plan([task("A", due: at(2026, 11, 27, 17, 0))])
        XCTAssertTrue(plans.isEmpty)
    }

    func testMorningDigestCountsTodayAndTomorrow() {
        let plans = plan([task("A", due: at(2026, 11, 27, 17, 0)),
                          task("B", due: at(2026, 11, 28, 8, 50)),
                          task("C", due: at(2026, 12, 10, 17, 0))]) { $0.morningEnabled = true }
        let mornings = plans.filter { $0.kind == .morning }
        // 今日か明日が締め切りの提出物がある朝(11/27 と 11/28)だけ鳴る
        XCTAssertEqual(mornings.map(\.fireDate), [at(2026, 11, 27, 7, 30), at(2026, 11, 28, 7, 30)])

        XCTAssertEqual(mornings[0].identifier, "morning-20261127")
        XCTAssertEqual(mornings[0].title, "今日締め切り 1 件・明日 1 件")
        XCTAssertEqual(mornings[0].body, "・ 今日 17:00 情報システム 課題A\n・ 明日 8:50 情報システム 課題B")

        // 11/28 の朝には A の締め切りが過ぎているので、期限切れとして数える
        XCTAssertEqual(mornings[1].title, "今日締め切り 1 件・明日 0 件(期限切れ 1)")
        XCTAssertEqual(mornings[1].body, "・ 今日 8:50 情報システム 課題B")
    }

    func testMorningDigestUsesConfiguredTimeAndShortensLongLists() {
        let tasks = (0..<6).map { task("\($0)", due: at(2026, 11, 27, 10 + $0, 0)) }
        let plans = plan(tasks) {
            $0.morningEnabled = true
            $0.morningHour = 6
            $0.morningMinute = 45
        }
        let first = plans.first { $0.kind == .morning }
        XCTAssertEqual(first?.fireDate, at(2026, 11, 27, 6, 45))
        XCTAssertEqual(first?.title, "今日締め切り 6 件・明日 0 件")
        // 本文は最大 4 件 + 「ほか 2 件」
        XCTAssertEqual(first?.body.components(separatedBy: "\n").count, 5)
        XCTAssertTrue(first?.body.hasSuffix("ほか 2 件") ?? false)
    }

    // MARK: 着手日の通知

    func testStartReminderFiresAtStartDate() {
        let plans = plan([task("A", due: at(2026, 12, 3, 17, 0), start: at(2026, 11, 30, 9, 0))])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].kind, .start(taskID: "A"))
        XCTAssertEqual(plans[0].identifier, "task-A-start")
        XCTAssertEqual(plans[0].fireDate, at(2026, 11, 30, 9, 0))
        XCTAssertEqual(plans[0].title, "【情報システム】課題A")
        XCTAssertEqual(plans[0].body, "そろそろ取りかかる予定の日時です。締め切り 12/3(木) 17:00(あと 3 日)")
    }

    func testStartReminderIsSkippedWhenPastOrAfterDeadline() {
        // すでに過ぎた着手日、締め切りより後の着手日は通知しない
        let plans = plan([task("A", due: at(2026, 12, 3, 17, 0), start: at(2026, 11, 25, 9, 0)),
                          task("B", due: at(2026, 12, 3, 17, 0), start: at(2026, 12, 4, 9, 0))])
        XCTAssertTrue(plans.isEmpty)
    }

    func testStartReminderComesWithDeadlineReminders() {
        let plans = plan([task("A", due: at(2026, 12, 3, 17, 0), rules: [.hoursBefore(3)],
                               start: at(2026, 11, 30, 9, 0))])
        XCTAssertEqual(plans.map(\.kind), [.start(taskID: "A"), .individual(taskID: "A")])
        XCTAssertEqual(plans.map(\.fireDate), [at(2026, 11, 30, 9, 0), at(2026, 12, 3, 14, 0)])
    }

    // MARK: 64 件の上限

    func testReservedSlotsReduceIndividualLimit() {
        // 遠い先の 60 件(朝のまとめには出てこない)。空けておく 5 件の分だけ個別の枠が減る
        let tasks = (0..<60).map { task("\($0)", due: tokyo.date(byAdding: .day, value: $0, to: at(2026, 12, 20, 17, 0))!,
                                        rules: [.hoursBefore(3)]) }
        XCTAssertEqual(plan(tasks).count, 49)
        XCTAssertEqual(plan(tasks) { $0.reservedSlots = 5 }.count, 44)
    }

    func testMorningDigestsTakeSlotsFromIndividual() {
        // 明日から毎日 1 件ずつ締め切り → 朝のまとめが 7 件。個別は 49 - 7 = 42 件に減り、合計は 49 件のまま
        let tasks = (0..<60).map { task("\($0)", due: tokyo.date(byAdding: .day, value: $0, to: at(2026, 11, 27, 17, 0))!,
                                        rules: [.hoursBefore(3)]) }
        let plans = plan(tasks) { $0.morningEnabled = true }
        XCTAssertEqual(plans.filter { $0.kind == .morning }.count, 7)
        XCTAssertEqual(plans.filter { if case .individual = $0.kind { return true } else { return false } }.count, 42)
        XCTAssertEqual(plans.count, 49)
    }
}
