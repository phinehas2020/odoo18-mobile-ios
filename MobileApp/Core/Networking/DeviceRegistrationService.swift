import Foundation

final class DeviceRegistrationService {
    func register(apiClient: APIClient) async {
        let token = UserDefaults.standard.string(forKey: "apns_token")
        let payload = DeviceRegisterPayload(
            deviceId: DeviceStore.shared.deviceId,
            deviceName: DeviceStore.shared.deviceName,
            platform: "ios",
            model: DeviceStore.shared.deviceName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            pushToken: token
        )
        do {
            let body = try DateCoding.encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/device/register", method: "POST", body: body)
            try await apiClient.sendNoResponse(endpoint)
        } catch {
            // ignore
        }
    }

    func heartbeat(apiClient: APIClient) async {
        let token = UserDefaults.standard.string(forKey: "apns_token")
        let payload = DeviceHeartbeatPayload(
            deviceId: DeviceStore.shared.deviceId,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            pushToken: token
        )
        do {
            let body = try DateCoding.encoder.encode(payload)
            let endpoint = Endpoint(path: "/api/v1/device/heartbeat", method: "POST", body: body)
            try await apiClient.sendNoResponse(endpoint)
        } catch {
            // ignore
        }
    }
}

struct DeviceRegisterPayload: Codable {
    let deviceId: String
    let deviceName: String
    let platform: String
    let model: String
    let osVersion: String
    let appVersion: String?
    let pushToken: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform, model
        case osVersion = "os_version"
        case appVersion = "app_version"
        case pushToken = "push_token"
    }
}

struct DeviceHeartbeatPayload: Codable {
    let deviceId: String
    let appVersion: String?
    let osVersion: String
    let pushToken: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case pushToken = "push_token"
    }
}
