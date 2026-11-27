import XCTest
@testable import KadaiCore

/// テスト(試験)の残り日数・通知・取り込みのテスト
final class ExamTests: XCTestCase {
    let now = at(2026, 11, 26, 12, 0)   // 木曜 12:00

    // MARK: 残り日数

    func testDaysLeftCountsCalendarDays() {
        // 日付で数えるので、テストの時刻が朝でも夜でも同じ日数になる
        XCTAssertEqual(ExamCountdown.daysLeft(until: at(2026, 12, 2, 9, 0), now: now, calendar: tokyo), 6)
        XCTAssertEqual(ExamCountdown.daysLeft(until: at(2026, 12, 2, 23, 0), now: now, calendar: tokyo), 6)
        XCTAssertEqual(ExamCountdown.daysLeft(until: at(2026, 11, 26, 18, 0), now: now, calendar: tokyo), 0)
        XCTAssertEqual(ExamCountdown.daysLeft(until: at(2026, 11, 25, 9, 0), now: now, calendar: tokyo), -1)
    }

    func testCountdownText() {
        XCTAssertEqual(ExamCountdown.text(until: at(2026, 12, 2, 9, 0), now: now, calendar: tokyo), "あと 6 日")
        XCTAssertEqual(ExamCountdown.text(until: at(2026, 11, 27, 9, 0), now: now, calendar: tokyo), "明日")
        // 明日の 0:30 は 12 時間半後だが、日付が変わるので「明日」
        XCTAssertEqual(ExamCountdown.text(until: at(2026, 11, 27, 0, 30), now: now, calendar: tokyo), "明日")
        XCTAssertEqual(ExamCountdown.text(until: at(2026, 11, 26, 15, 0), now: now, calendar: tokyo), "今日(あと 3 時間)")
        XCTAssertEqual(ExamCountdown.text(until: at(2026, 11, 26, 9, 0), now: now, calendar: tokyo), "終了")
    }

    // MARK: 通知

    func plan(_ exams: [ExamSnapshot], tasks: [TaskSnapshot] = [],
              configure: (inout PlannerSettings) -> Void = { _ in }) -> [PlannedNotification] {
        var settings = PlannerSettings()
        settings.nightlyEnabled = false
        settings.examEnabled = true
        configure(&settings)
        return NotificationPlanner.plan(tasks: tasks, exams: exams, settings: settings, signingExpiry: nil,
                                        now: now, calendar: tokyo)
    }

    func testExamRemindersFireSevenThreeAndOneDayBefore() {
        let exam = ExamSnapshot(id: "E", subject: "線形代数", title: "期末試験", date: at(2026, 12, 10, 9, 0))
        let plans = plan([exam])
        XCTAssertEqual(plans.map(\.fireDate), [at(2026, 12, 3, 21, 0), at(2026, 12, 7, 21, 0), at(2026, 12, 9, 21, 0)])
        XCTAssertTrue(plans.allSatisfy { $0.kind == .exam(examID: "E") })
        XCTAssertEqual(plans[0].title, "【線形代数】期末試験")
        XCTAssertEqual(plans[0].body, "テストは 12/10(木) 9:00 です(あと 7 日)")
        XCTAssertEqual(plans[2].body, "テストは 12/10(木) 9:00 です(明日)")
    }

    func testPastRemindersAndPastExamsAreSkipped() {
        // 5 日後のテスト: 7 日前はもう過ぎているので、3 日前と前日だけ
        let soon = ExamSnapshot(id: "S", subject: "", title: "小テスト", date: at(2026, 12, 1, 13, 0))
        XCTAssertEqual(plan([soon]).map(\.fireDate), [at(2026, 11, 28, 21, 0), at(2026, 11, 30, 21, 0)])
        XCTAssertEqual(plan([soon]).first?.title, "小テスト")
        // 終わったテストは通知しない
        let past = ExamSnapshot(id: "P", subject: "", title: "中間試験", date: at(2026, 11, 20, 9, 0))
        XCTAssertTrue(plan([past]).isEmpty)
    }

    func testExamRemindersAreOffByDefaultAndFollowNightlyTime() {
        let exam = ExamSnapshot(id: "E", subject: "", title: "期末試験", date: at(2026, 12, 10, 9, 0))
        XCTAssertTrue(plan([exam]) { $0.examEnabled = false }.isEmpty)
        let plans = plan([exam]) { $0.nightlyHour = 20; $0.nightlyMinute = 30; $0.examDaysBefore = [1] }
        XCTAssertEqual(plans.map(\.fireDate), [at(2026, 12, 9, 20, 30)])
    }

    func testExamRemindersShareTheIndividualLimit() {
        // 提出物の通知 60 件 + テストの通知。合わせて枠(49 件)まで、鳴る時刻が近い順に予約する
        let tasks = (0..<60).map { TaskSnapshot(id: "\($0)", subject: "", title: "課題",
                                                due: tokyo.date(byAdding: .day, value: $0, to: at(2026, 12, 20, 17, 0))!,
                                                rules: [.hoursBefore(3)]) }
        let exam = ExamSnapshot(id: "E", subject: "", title: "期末試験", date: at(2026, 12, 10, 9, 0))
        let plans = plan([exam], tasks: tasks)
        XCTAssertEqual(plans.count, 49)
        // テストは提出物より早いので、3 件とも枠に入る
        XCTAssertEqual(plans.filter { $0.kind == .exam(examID: "E") }.count, 3)
    }

    // MARK: 取り込み

    func testExamLinesInImportText() {
        let text = """
        #kadai v1
        #exam 線形代数 | 期末試験 | 2026-12-10 09:00 | 範囲は全部
        #テスト 離散数学 | 小テスト | 2026-12-01
        #exam 科目だけ
        #exam 論理回路 | 小テスト | あした
        """
        let result = ImportParser.parse(text, calendar: tokyo)
        XCTAssertEqual(result.exams, [
            ImportExam(subject: "線形代数", title: "期末試験", date: at(2026, 12, 10, 9, 0), hasTime: true, memo: "範囲は全部"),
            // 時刻がなければ初期時刻(8:50)
            ImportExam(subject: "離散数学", title: "小テスト", date: at(2026, 12, 1, 8, 50), hasTime: false, memo: ""),
        ])
        XCTAssertEqual(result.errors.map(\.lineNumber), [4, 5])
        // テストの行は、提出物としては読まない
        XCTAssertTrue(result.items.isEmpty)
    }
}
