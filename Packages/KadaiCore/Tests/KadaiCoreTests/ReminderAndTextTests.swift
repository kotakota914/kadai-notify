import XCTest
@testable import KadaiCore

final class ReminderRuleTests: XCTestCase {
    let due = at(2026, 12, 3, 17, 0)   // 木曜 17:00

    func testDaysBeforeFiresAtGivenTime() {
        XCTAssertEqual(ReminderRule.daysBefore(3).fireDate(forDeadline: due, calendar: tokyo), at(2026, 11, 30, 21, 0))
        XCTAssertEqual(ReminderRule.daysBefore(1).fireDate(forDeadline: due, calendar: tokyo), at(2026, 12, 2, 21, 0))
        XCTAssertEqual(ReminderRule.daysBefore(0, hour: 8).fireDate(forDeadline: due, calendar: tokyo), at(2026, 12, 3, 8, 0))
    }

    func testHoursBefore() {
        XCTAssertEqual(ReminderRule.hoursBefore(3).fireDate(forDeadline: due, calendar: tokyo), at(2026, 12, 3, 14, 0))
    }

    func testLabels() {
        XCTAssertEqual(ReminderRule.daysBefore(3).label, "3 日前の 21:00")
        XCTAssertEqual(ReminderRule.daysBefore(0, hour: 8).label, "当日の 8:00")
        XCTAssertEqual(ReminderRule.hoursBefore(3).label, "3 時間前")
        XCTAssertEqual(ReminderRule.summary([]), "通知しない")
    }

    func testResolveOrderTaskThenSubjectThenGlobal() {
        let global = ReminderRule.defaultRules
        let subject = [ReminderRule.daysBefore(7)]
        let task = [ReminderRule.hoursBefore(1)]
        XCTAssertEqual(ReminderRule.resolve(task: nil, subject: nil, global: global), global)
        XCTAssertEqual(ReminderRule.resolve(task: nil, subject: subject, global: global), subject)
        XCTAssertEqual(ReminderRule.resolve(task: task, subject: subject, global: global), task)
        // 空の配列は「通知しない」という上書き
        XCTAssertEqual(ReminderRule.resolve(task: nil, subject: [], global: global), [])
    }

    func testEncodeDecodeRoundTrip() {
        let rules = [ReminderRule.daysBefore(3), .hoursBefore(2)]
        XCTAssertEqual(ReminderRule.decodeList(ReminderRule.encodeList(rules)), rules)
        XCTAssertNil(ReminderRule.decodeList(nil))
        XCTAssertEqual(ReminderRule.decodeList(ReminderRule.encodeList([])), [])
    }
}

final class DeadlineTextTests: XCTestCase {
    func testDateTime() {
        XCTAssertEqual(DeadlineText.dateTime(at(2026, 12, 3, 17, 0), calendar: tokyo), "12/3(木) 17:00")
        XCTAssertEqual(DeadlineText.dateTime(at(2026, 12, 5, 8, 50), calendar: tokyo), "12/5(土) 8:50")
        XCTAssertEqual(DeadlineText.date(at(2026, 11, 30), calendar: tokyo), "11/30(月)")
    }

    func testRelativeDay() {
        let now = at(2026, 12, 3, 10, 0)
        XCTAssertEqual(DeadlineText.relativeDay(at(2026, 12, 3, 17, 0), now: now, calendar: tokyo), "今日 17:00")
        XCTAssertEqual(DeadlineText.relativeDay(at(2026, 12, 4, 9, 5), now: now, calendar: tokyo), "明日 9:05")
        XCTAssertEqual(DeadlineText.relativeDay(at(2026, 12, 5, 8, 50), now: now, calendar: tokyo), "12/5(土) 8:50")
    }

    func testRemaining() {
        let now = at(2026, 12, 1, 12, 0)
        func remaining(_ seconds: TimeInterval) -> String {
            DeadlineText.remaining(until: now.addingTimeInterval(seconds), now: now)
        }
        XCTAssertEqual(remaining(2 * 86400), "あと 2 日")
        XCTAssertEqual(remaining(86400 + 5 * 3600), "あと 1 日 5 時間")
        XCTAssertEqual(remaining(86400), "あと 1 日")
        XCTAssertEqual(remaining(3 * 3600), "あと 3 時間")
        XCTAssertEqual(remaining(25 * 60), "あと 25 分")
        XCTAssertEqual(remaining(30), "まもなく")
        XCTAssertEqual(remaining(-30 * 60), "30 分超過")
        XCTAssertEqual(remaining(-5 * 3600), "5 時間超過")
        XCTAssertEqual(remaining(-3 * 86400), "3 日超過")
    }

    func testDueGroup() {
        let now = at(2026, 12, 3, 10, 0)
        XCTAssertEqual(DueGroup.group(for: at(2026, 12, 3, 9, 0), now: now, calendar: tokyo), .overdue)
        XCTAssertEqual(DueGroup.group(for: at(2026, 12, 3, 17, 0), now: now, calendar: tokyo), .today)
        XCTAssertEqual(DueGroup.group(for: at(2026, 12, 4, 1, 0), now: now, calendar: tokyo), .tomorrow)
        XCTAssertEqual(DueGroup.group(for: at(2026, 12, 5, 8, 50), now: now, calendar: tokyo), .later)
    }
}

final class SubjectPaletteTests: XCTestCase {
    func testNextColorPicksLeastUsed() {
        let colors = SubjectPalette.colors
        XCTAssertEqual(SubjectPalette.nextColor(used: []), colors[0])
        XCTAssertEqual(SubjectPalette.nextColor(used: [colors[0]]), colors[1])
        XCTAssertEqual(SubjectPalette.nextColor(used: colors), colors[0])
    }

    func testRGB() {
        let red = SubjectPalette.rgb(hex: "#FF0000")
        XCTAssertEqual(red?.red, 1)
        XCTAssertEqual(red?.green, 0)
        XCTAssertNil(SubjectPalette.rgb(hex: "xyz"))
    }
}

final class ProvisioningProfileTests: XCTestCase {
    func testReadsExpirationDateFromEmbeddedPlist() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ExpirationDate</key>
            <date>2026-12-03T05:20:00Z</date>
            <key>Name</key>
            <string>iOS Team Provisioning Profile: *</string>
        </dict>
        </plist>
        """
        // 本物のファイルは前後に署名のバイト列が付いているので、それをまねる
        var data = Data([0x30, 0x82, 0x0F, 0x00])
        data.append(Data(xml.utf8))
        data.append(Data([0x00, 0xA0, 0x82]))

        let expected = ISO8601DateFormatter().date(from: "2026-12-03T05:20:00Z")
        XCTAssertEqual(ProvisioningProfile.expirationDate(fromProfileData: data), expected)
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(ProvisioningProfile.expirationDate(fromProfileData: Data("hello".utf8)))
    }
}
