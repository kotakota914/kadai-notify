import SwiftUI
import KadaiCore

extension Color {
    /// "#RRGGBB" の文字から色を作る(読めなければ灰色)
    init(hex: String) {
        if let rgb = SubjectPalette.rgb(hex: hex) {
            self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } else {
            self.init(white: 0.6)
        }
    }
}

extension DueGroup {
    /// 一覧やウィジェットでの文字の色
    var color: Color {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .tomorrow: return .primary
        case .later: return .secondary
        }
    }
}
