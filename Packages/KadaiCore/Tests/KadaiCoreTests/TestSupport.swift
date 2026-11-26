import Foundation

/// テストでは日本時間に固定したカレンダーを使う(実行するマシンの設定に左右されないように)
let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    calendar.locale = Locale(identifier: "ja_JP")
    return calendar
}()

/// 日本時間の日時を作る。例: at(2026, 12, 3, 17, 0) = 2026/12/3(木) 17:00
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
