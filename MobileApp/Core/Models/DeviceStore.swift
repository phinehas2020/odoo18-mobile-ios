import Foundation
import UIKit

final class DeviceStore {
    static let shared = DeviceStore()

    private let deviceIdKey = "mobile_device_id"
    private let userDefaults = UserDefaults.standard

    var deviceId: String {
        if let existing = userDefaults.string(forKey: deviceIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        userDefaults.set(newId, forKey: deviceIdKey)
        return newId
    }

    var deviceName: String {
        UIDevice.current.name
    }
}
