import XCTest
@testable import KadaiCore

final class AssignmentKindTests: XCTestCase {
    func testGuessFromTitle() {
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "授業8小テスト"), .quiz)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "第2回学習確認問題"), .quiz)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "【レポート1】MATLAB 数字認識 ①"), .report)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "授業9アンケート"), .survey)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "自己評価"), .other)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "課題01【期限切れ提出】"), .assignment)
    }

    func testUnknownTitleIsAssignment() {
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "振り返りシート"), .assignment)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: ""), .assignment)
    }

    func testEnglishWordsIgnoreCase() {
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "Weekly Quiz 3"), .quiz)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "Final REPORT"), .report)
    }

    func testSiteNamesWinOverOtherWords() {
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "Moodle Unit 5 Quiz"), .moodle)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "paiza 練習問題 B ランク"), .paiza)
        XCTAssertEqual(AssignmentKind.guess(fromTitle: "ムードルの課題"), .moodle)
    }

    func testLabelsAndRawValuesRoundTrip() {
        XCTAssertEqual(AssignmentKind.allCases.map(\.label), ["課題", "レポート", "小テスト", "アンケート", "Moodle", "paiza", "その他"])
        for kind in AssignmentKind.allCases {
            XCTAssertEqual(AssignmentKind(rawValue: kind.rawValue), kind)
        }
    }
}

final class AssignmentRankTests: XCTestCase {
    func testLabelsAndOrder() {
        XCTAssertEqual(AssignmentRank.allCases.map(\.label), ["S", "A", "B", "C"])
        // 並べ替えると、重要な順(S → C)になる
        XCTAssertEqual([AssignmentRank.c, .s, .b, .a].sorted(), [.s, .a, .b, .c])
        XCTAssertLessThan(AssignmentRank.s, AssignmentRank.a)
    }

    func testRawValuesRoundTrip() {
        for rank in AssignmentRank.allCases {
            XCTAssertEqual(AssignmentRank(rawValue: rank.rawValue), rank)
        }
        XCTAssertNil(AssignmentRank(rawValue: "z"))
    }
}

final class MonthGridTests: XCTestCase {
    func testMonthStartingOnSundayHasNoLeadingDays() {
        // 2026 年 11 月 1 日は日曜。30 日あるので 5 週 = 35 マス
        let days = MonthGrid.days(inMonthOf: at(2026, 11, 27, 15, 0), calendar: tokyo)
        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(days.first, at(2026, 11, 1))
        XCTAssertEqual(days.last, at(2026, 12, 5))
    }

    func testLeadingDaysComeFromPreviousMonth() {
        // 2026 年 12 月 1 日は火曜 → 前に 11/29(日)・11/30(月) が並ぶ
        let days = MonthGrid.days(inMonthOf: at(2026, 12, 10), calendar: tokyo)
        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(days.first, at(2026, 11, 29))
        XCTAssertEqual(days[2], at(2026, 12, 1))
        XCTAssertEqual(days.last, at(2027, 1, 2))
    }

    func testFourWeekAndSixWeekMonths() {
        // 2026 年 2 月は 1 日が日曜で 28 日 → ちょうど 4 週
        XCTAssertEqual(MonthGrid.days(inMonthOf: at(2026, 2, 14), calendar: tokyo).count, 28)
        // 2026 年 5 月は 1 日が金曜で 31 日 → 6 週
        XCTAssertEqual(MonthGrid.days(inMonthOf: at(2026, 5, 14), calendar: tokyo).count, 42)
    }

    func testAddingMonthsCrossesYear() {
        XCTAssertEqual(MonthGrid.addingMonths(2, to: at(2026, 11, 27), calendar: tokyo), at(2027, 1, 1))
        XCTAssertEqual(MonthGrid.addingMonths(-1, to: at(2027, 1, 15), calendar: tokyo), at(2026, 12, 1))
    }

    func testTitleAndHeaders() {
        XCTAssertEqual(MonthGrid.title(at(2026, 11, 27), calendar: tokyo), "2026年11月")
        XCTAssertEqual(MonthGrid.weekdayHeaders(calendar: tokyo), ["日", "月", "火", "水", "木", "金", "土"])
    }
}

final class GanttLayoutTests: XCTestCase {
    private let rangeStart = at(2026, 11, 20)

    func testBarInsideRange() {
        // 11/22 0:00 → 11/25 12:00 は、左端から 2 日目に始まる 3.5 日の棒
        let bar = GanttLayout.bar(start: at(2026, 11, 22), end: at(2026, 11, 25, 12, 0),
                                  rangeStart: rangeStart, rangeDays: 28)
        XCTAssertEqual(bar, GanttBar(offsetDays: 2, lengthDays: 3.5,
                                     startsBeforeRange: false, endsAfterRange: false))
    }

    func testBarClampedAtBothEnds() {
        let bar = GanttLayout.bar(start: at(2026, 10, 1), end: at(2027, 3, 31),
                                  rangeStart: rangeStart, rangeDays: 28)
        XCTAssertEqual(bar, GanttBar(offsetDays: 0, lengthDays: 28,
                                     startsBeforeRange: true, endsAfterRange: true))
    }

    func testBarOutsideRangeIsNil() {
        // 表示範囲より前に終わっている
        XCTAssertNil(GanttLayout.bar(start: at(2026, 11, 1), end: at(2026, 11, 19),
                                     rangeStart: rangeStart, rangeDays: 28))
        // 表示範囲より後に始まる
        XCTAssertNil(GanttLayout.bar(start: at(2027, 1, 1), end: at(2027, 1, 5),
                                     rangeStart: rangeStart, rangeDays: 28))
    }

    func testShortBarGetsMinimumLength() {
        // 登録が締め切りの 1 時間前でも、見える長さ(半日)の棒になる
        let bar = GanttLayout.bar(start: at(2026, 11, 25, 16, 0), end: at(2026, 11, 25, 17, 0),
                                  rangeStart: rangeStart, rangeDays: 28)
        XCTAssertEqual(bar?.lengthDays, GanttLayout.minimumLengthDays)
        XCTAssertEqual((bar?.offsetDays ?? 0) + (bar?.lengthDays ?? 0), 5 + 17.0 / 24, accuracy: 0.0001)
    }

    func testStartAfterEndIsTreatedAsShortBarAtDeadline() {
        // 締め切り後に登録した場合(始まり > 終わり)も、締め切りの位置に棒が出る
        let bar = GanttLayout.bar(start: at(2026, 11, 27), end: at(2026, 11, 25, 12, 0),
                                  rangeStart: rangeStart, rangeDays: 28)
        XCTAssertEqual(bar?.lengthDays, GanttLayout.minimumLengthDays)
        XCTAssertEqual(bar?.offsetDays, 5)
    }

    func testRangeDays() {
        XCTAssertEqual(GanttLayout.rangeDays(latestDue: nil, rangeStart: rangeStart), 28)
        // 近い締め切りしかなくても 28 日は表示する
        XCTAssertEqual(GanttLayout.rangeDays(latestDue: at(2026, 11, 25), rangeStart: rangeStart), 28)
        // 12/31 23:59 が入るように伸びる(41.99… 日 → 切り上げ 42 + 余白 2)
        XCTAssertEqual(GanttLayout.rangeDays(latestDue: at(2026, 12, 31, 23, 59), rangeStart: rangeStart), 44)
        // 遠すぎる締め切りは上限で打ち切る
        XCTAssertEqual(GanttLayout.rangeDays(latestDue: at(2028, 1, 1), rangeStart: rangeStart), 180)
    }
}

final class ImportSubjectLineTests: XCTestCase {
    func testSubjectLinesAreCollected() {
        let text = """
        #kadai v1
        #subject 線形代数学
        #科目 離散数学
        #subject: 確率と統計
        情報システム | 第8回レポート | 2026-12-03 17:00 | メモ
        """
        let result = ImportParser.parse(text, calendar: tokyo)
        XCTAssertEqual(result.subjects, ["線形代数学", "離散数学", "確率と統計"])
        // 科目の行があっても、課題の行はこれまでどおり読める
        XCTAssertEqual(result.items.map(\.title), ["第8回レポート"])
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testDuplicateSubjectLinesAreMerged() {
        // 空白や全角・半角の違いだけなら同じ科目とみなす
        let text = "#kadai v1\n#subject 修学基礎B\n#subject 修学基礎Ｂ\n#subject 修学 基礎B"
        XCTAssertEqual(ImportParser.parse(text, calendar: tokyo).subjects, ["修学基礎B"])
    }

    func testOtherCommentLinesAreStillIgnored() {
        let text = "#kadai v1\n# これはメモ\n#subjects 複数形は対象外\n#subject\n#subject   "
        let result = ImportParser.parse(text, calendar: tokyo)
        XCTAssertEqual(result.subjects, [])
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
    }
}

final class ImportGradingLineTests: XCTestCase {
    func testGradingLines() {
        let text = """
        #kadai v1
        #grading 線形代数学 | 試験 60% / 小テスト 30% / レポート 10%
        #評価 離散数学 | 試験 70% | 小テスト 30%
        #grading 線形代数学 | 試験 50% / 小テスト 50%
        #grading 科目だけ
        """
        let result = ImportParser.parse(text, calendar: tokyo)
        // 同じ科目が 2 回出てきたら後のものを使う。文の中の「|」はそのまま残る
        XCTAssertEqual(result.gradings, [ImportGrading(subject: "離散数学", note: "試験 70% | 小テスト 30%"),
                                         ImportGrading(subject: "線形代数学", note: "試験 50% / 小テスト 50%")])
        XCTAssertEqual(result.errors.map(\.lineNumber), [5])
        XCTAssertTrue(result.items.isEmpty)
    }
}
