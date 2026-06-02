import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
import FocusedCore

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    #if canImport(UserNotifications)
    private var center: UNUserNotificationCenter?
    #endif
    private var authorized = false
    private let isAvailable: Bool
    var onActivate: ((String) -> Void)?

    override init() {
        // UNUserNotificationCenter.current() throws NSInternalInconsistencyException
        // when run from a non-bundled executable (e.g. `swift run`). Detect that
        // and disable notifications rather than crashing at launch.
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
        self.isAvailable = bundled
        super.init()
        #if canImport(UserNotifications)
        if bundled {
            self.center = UNUserNotificationCenter.current()
            self.center?.delegate = self
        }
        #endif
    }

    func requestAuthorizationIfNeeded() async {
        guard isAvailable else { return }
        #if canImport(UserNotifications)
        guard let center else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let s = await center.notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        #endif
    }

    func fireIdle(sessionName: String, sessionId: String, body: String) {
        guard isAvailable, authorized else { return }
        #if canImport(UserNotifications)
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(sessionName) is done"
        content.body = body
        content.userInfo = ["sessionId": sessionId]
        let request = UNNotificationRequest(identifier: sessionId, content: content, trigger: nil)
        center.add(request)
        #endif
    }
}

#if canImport(UserNotifications)
extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["sessionId"] as? String ?? ""
        await MainActor.run { self.onActivate?(id) }
    }
}
#endif
