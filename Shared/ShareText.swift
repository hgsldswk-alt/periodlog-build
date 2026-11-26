import Foundation

enum ShareText {
    static var storeURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id)
    }
    static var invitation: String {
        let text = L.t("一个很干净的经期记录 App，不用注册、没有广告，数据只存在自己手机里。") + "\n" + L.t("#经期记录 #女生必备App #隐私")
        return text + (storeURL.map { "\n" + $0.absoluteString } ?? "")
    }
    static func code(_ code: String) -> String { L.t("复制整段，在「隐私经期记录」里打开即可添加。") + "\n" + code }
}
