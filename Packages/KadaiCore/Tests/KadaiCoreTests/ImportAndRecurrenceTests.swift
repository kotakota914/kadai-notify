import XCTest
@testable import KadaiCore

final class ImportParserTests: XCTestCase {
    func parse(_ text: String) -> ImportResult {
        ImportParser.parse(text, defaultHour: 8, defaultMinute: 50, calendar: tokyo)
    }

    // 受け入れ条件 F-08: 要件定義書 7.3 の例
    func testExampleFromRequirements() {
        let result = parse("""
        #kadai v1
        情報システム | 第8回レポート | 2026-12-03 17:00 | A4 2枚、Moodleに提出
        論理回路 | 演習課題5 | 2026-12-04 23:59 |
        PD入門 | 振り返りシート | 2026-12-05 | 時刻不明
        """)
        XCTAssertTrue(result.headerFound)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.items.count, 3)

        XCTAssertEqual(result.items[0].subject, "情報システム")
        XCTAssertEqual(result.items[0].title, "第8回レポート")
        XCTAssertEqual(result.items[0].due, at(2026, 12, 3, 17, 0))
        XCTAssertEqual(result.items[0].memo, "A4 2枚、Moodleに提出")
        XCTAssertEqual(result.items[0].lineNumber, 2)

        XCTAssertEqual(result.items[1].memo, "")
        XCTAssertTrue(result.items[1].hasTime)

        // 時刻がない → 8:50
        XCTAssertEqual(result.items[2].due, at(2026, 12, 5, 8, 50))
        XCTAssertFalse(result.items[2].hasTime)
    }

    func testMissingHeader() {
        let result = parse("情報システム | 第8回レポート | 2026-12-03 17:00")
        XCTAssertFalse(result.headerFound)
        XCTAssertTrue(result.items.isEmpty)
    }

    // Claude が前置きやコードブロック、見出し行を付けても読める
    func testPreambleCodeFenceAndColumnHeaderAreIgnored() {
        let result = parse("""
        以下が提出物の一覧です。
        ```
        #kadai v1
        科目 | 課題名 | 締め切り | メモ
        知能情報入門 | 小テスト | 2026/12/3 9:00
        ```
        """)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].due, at(2026, 12, 3, 9, 0))
    }

    func testFullWidthCharacters() {
        let result = parse("＃ｋａｄａｉ　ｖ１\n情報｜課題｜２０２６－１２－０３　１７：００")
        XCTAssertTrue(result.headerFound)
        XCTAssertEqual(result.items.first?.due, at(2026, 12, 3, 17, 0))
    }

    func testCRLFAndISOStyleTime() {
        let result = parse("#kadai v1\r\nA | B | 2026-12-03T09:30\r\n")
        XCTAssertEqual(result.items.first?.due, at(2026, 12, 3, 9, 30))
    }

    func testErrorsAreReportedWithReasons() {
        let result = parse("""
        #kadai v1
        A | B
         | B | 2026-12-03
        A |  | 2026-12-03
        A | B | 明日
        A | B | 2026-02-30
        A | B | 2026-12-03 25:00
        """)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.errors.map(\.lineNumber), [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(result.errors[0].reason, "「|」で区切られた項目が 3 つ未満です")
        XCTAssertEqual(result.errors[1].reason, "科目が空です")
        XCTAssertEqual(result.errors[2].reason, "課題名が空です")
    }
}

final class ImportMatcherTests: XCTestCase {
    let existing = [ExistingTaskKey(id: "X", subject: "情報システム", title: "第8回レポート",
                                    due: at(2026, 12, 3, 17, 0))]

    func item(_ title: String = "第8回レポート", subject: String = "情報システム",
              due: Date = at(2026, 12, 3, 17, 0), hasTime: Bool = true) -> ImportItem {
        ImportItem(subject: subject, title: title, due: due, hasTime: hasTime, memo: "", lineNumber: 2)
    }

    func match(_ items: [ImportItem]) -> [ImportMatch] {
        ImportMatcher.matchAll(items, existing: existing, calendar: tokyo)
    }

    func testDuplicateUpdateAndNew() {
        XCTAssertEqual(match([item()]), [.duplicate(existingID: "X")])
        XCTAssertEqual(match([item(due: at(2026, 12, 3, 18, 0))]), [.update(existingID: "X")])
        // 取り込み側に時刻がない(8:50)ときは、登録済みの時刻を優先して「登録済み」
        XCTAssertEqual(match([item(due: at(2026, 12, 3, 8, 50), hasTime: false)]), [.duplicate(existingID: "X")])
        XCTAssertEqual(match([item("第9回レポート")]), [.new])
        XCTAssertEqual(match([item(due: at(2026, 12, 10, 17, 0))]), [.new])
    }

    // 受け入れ条件 F-08: 同じテキストを 2 回貼ると全部「登録済み」(ここでは空白の違いも同じとみなす)
    func testSpacingDifferencesAreIgnoredAndBatchDuplicatesDetected() {
        XCTAssertEqual(match([item(subject: "情報 システム")]), [.duplicate(existingID: "X")])
        let twice = [item("新しい課題"), item("新しい課題")]
        XCTAssertEqual(match(twice), [.new, .duplicate(existingID: nil)])
    }
}

final class RecurrenceTests: XCTestCase {
    let now = at(2026, 11, 26, 12, 0)   // 木曜 12:00

    func rule(start: Date = at(2026, 11, 26), end: Date? = nil) -> WeeklyRule {
        WeeklyRule(weekday: 5, hour: 17, minute: 0, startDate: start, endDate: end,
                   titlePattern: "第{n}回 小テスト")
    }

    // 受け入れ条件 F-07: 毎週木曜 17:00 → 14 日以内の 2 件
    func testCreatesOccurrencesWithinFourteenDays() {
        let result = RecurrenceGenerator.occurrences(rule: rule(), lastGeneratedDue: nil, now: now, calendar: tokyo)
        XCTAssertEqual(result.map(\.due), [at(2026, 11, 26, 17, 0), at(2026, 12, 3, 17, 0)])
        XCTAssertEqual(result.map(\.title), ["第1回 小テスト", "第2回 小テスト"])
    }

    // 1 週間後に開くと新しい回が増える。作成済み(削除済みも含む)の回は作り直さない
    func testOnlyNewOccurrencesAfterLastGenerated() {
        let result = RecurrenceGenerator.occurrences(rule: rule(), lastGeneratedDue: at(2026, 12, 3, 17, 0),
                                                     now: at(2026, 12, 4, 12, 0), calendar: tokyo)
        XCTAssertEqual(result.map(\.due), [at(2026, 12, 10, 17, 0), at(2026, 12, 17, 17, 0)])
        XCTAssertEqual(result.map(\.number), [3, 4])

        let nothingNew = RecurrenceGenerator.occurrences(rule: rule(), lastGeneratedDue: at(2026, 12, 3, 17, 0),
                                                         now: now, calendar: tokyo)
        XCTAssertTrue(nothingNew.isEmpty)
    }

    func testEndDateIsInclusive() {
        let untilThursday = RecurrenceGenerator.occurrences(rule: rule(end: at(2026, 12, 3)), lastGeneratedDue: nil,
                                                            now: now, calendar: tokyo)
        XCTAssertEqual(untilThursday.count, 2)
        let untilWednesday = RecurrenceGenerator.occurrences(rule: rule(end: at(2026, 12, 2)), lastGeneratedDue: nil,
                                                             now: now, calendar: tokyo)
        XCTAssertEqual(untilWednesday.count, 1)
    }

    func testNumbersCountFromStartDate() {
        // 11/1(日) 開始 → 1 回目は 11/5(木)、11/26 は 4 回目
        let result = RecurrenceGenerator.occurrences(rule: rule(start: at(2026, 11, 1)), lastGeneratedDue: nil,
                                                     now: now, calendar: tokyo)
        XCTAssertEqual(result.map(\.number), [4, 5])
    }

    func testInvalidWeekdayCreatesNothing() {
        var bad = rule()
        bad.weekday = 0
        XCTAssertTrue(RecurrenceGenerator.occurrences(rule: bad, lastGeneratedDue: nil, now: now, calendar: tokyo).isEmpty)
    }
}
