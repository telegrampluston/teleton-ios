import UIKit
import ForkTelegramInterface

struct DeviceInfo {
    let deviceId: String
    let osVersion: String
    let os: String
    let appVersion: String
    let locale: String
    
    init() {
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        self.osVersion = UIDevice.current.systemVersion
        self.os = "IOS"
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.locale = Locale.current.languageCode ?? "en"
    }
    
    func headers(interface: TelegramInterface?) -> [String: String] {
        [
            "x-device-id": deviceId,
            "x-device-operating-system": os,
            "x-device-operating-system-version": osVersion,
            "x-app-version": appVersion,
            "x-ime-client-request-id": UUID().uuidString,
            "accept-language": interface?.localeString ?? locale
        ]
    }
}
