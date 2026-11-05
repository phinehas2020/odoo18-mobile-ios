import Foundation
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // People are asked once after signing in (NotificationPermission). On launch,
        // authorized devices re-register so the server always has the current token.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apns_token")
        NotificationCenter.default.post(name: .apnsTokenUpdated, object: token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(name: .deepLinkReceived, object: userInfo)
    }

    /// Show assignments and announcements as banners even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

}

/// Asks for notification permission once, right after someone signs in, so employees
/// receive assignments and announcements without hunting for the setting.
enum NotificationPermission {
    @MainActor
    static func requestAfterSignIn(center: UNUserNotificationCenter = .current()) async {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            let allowed = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break   // They said no; Settings explains how to turn it back on.
        }
    }
}

extension Notification.Name {
    static let deepLinkReceived = Notification.Name("deepLinkReceived")
    static let apnsTokenUpdated = Notification.Name("apnsTokenUpdated")
}
