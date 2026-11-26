import Foundation

/// 科目に付ける 8 色。色は "#RRGGBB" の文字で保存する。
public enum SubjectPalette {
    public static let colors: [String] = [
        "#E5484D", "#F76B15", "#E2A336", "#30A46C",
        "#12A594", "#0090FF", "#6E56CF", "#D6409F",
    ]
    public static let names: [String] = ["赤", "オレンジ", "黄", "緑", "青緑", "青", "紫", "ピンク"]

    /// まだ使われていない(または使われた回数が一番少ない)色を、並び順の早いものから選ぶ
    public static func nextColor(used: [String]) -> String {
        let counts = Dictionary(used.map { ($0.uppercased(), 1) }, uniquingKeysWith: +)
        return colors.min { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? colors[0]
    }

    /// "#RRGGBB" を 0〜1 の赤・緑・青に分ける。読めなければ nil
    public static func rgb(hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }
}
