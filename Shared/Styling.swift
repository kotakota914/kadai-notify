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

extension AssignmentRank {
    /// ランクの札の色(S = 赤、A = オレンジ、B = 青、C = 灰色)
    var color: Color {
        switch self {
        case .s: return .red
        case .a: return .orange
        case .b: return .blue
        case .c: return .gray
        }
    }
}

/// ランクを表す小さな札(例: 赤地に白い「S」)
struct RankBadge: View {
    let rank: AssignmentRank

    var body: some View {
        Text(rank.label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(rank.color, in: Capsule())
            .accessibilityLabel("ランク \(rank.label)")
    }
}

/// テストの残り日数の色(近いほど目立つ色にする)
enum ExamStyle {
    static func color(daysLeft: Int) -> Color {
        switch daysLeft {
        case ...1: return .red
        case 2...3: return .orange
        case 4...7: return .accentColor
        default: return .primary
        }
    }
}
