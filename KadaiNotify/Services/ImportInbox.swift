import Foundation

/// Mac からケーブル経由で送られてきた取り込みテキストの「受け取り箱」。
///
/// Mac 側の `scripts/send-to-iphone.sh` が、アプリの書類フォルダ(Documents)に
/// `import.txt` という名前でファイルを置く。アプリは開いたときにそれを見つけて、
/// 取り込みの確認画面を出す。クリップボードの共有がうまく働かないときの代わりの道。
enum ImportInbox {
    static let fileName = "import.txt"

    /// 受け取り箱のファイルの場所(アプリの書類フォルダの中)
    static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    /// 受け取り箱にテキストがあれば読む。なければ nil。ファイルは消さない
    static func read() -> String? {
        guard let url = fileURL,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// 受け取り箱を空にする(確認画面を閉じたあとに呼ぶ)
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
