import Foundation

/// アプリに入っている署名のファイル(embedded.mobileprovision)から期限を読む。
/// 無料の Apple ID で入れたアプリは 7 日で期限が切れるので、その日時を知るために使う。
public enum ProvisioningProfile {
    /// ファイルは暗号の署名で包まれているが、中身の設定(plist という XML 形式)は
    /// 普通の文字として埋め込まれているので、「<?xml」から「</plist>」までを切り出して読む。
    public static func expirationDate(fromProfileData data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary["ExpirationDate"] as? Date
    }
}
