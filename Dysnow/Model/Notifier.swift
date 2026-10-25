import AppKit
import UserNotifications

/// Posts notifications: the system's in the app, a recording one in tests.
@MainActor
protocol Notifier: AnyObject {
    /// Asks for permission ahead of the first notification, so the question
    /// comes while the user is there to answer it.
    func prepare()
    /// `fileURL` is shown in the Finder when the notification is clicked.
    func post(title: String, body: String, fileURL: URL?)
}

/// macOS notifications, shown also while Dysnow is in front.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    private var askedForPermission = false
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func prepare() {
        guard !askedForPermission else { return }
        askedForPermission = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, fileURL: URL?) {
        prepare()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let fileURL { content.userInfo = ["file": fileURL.path] }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["file"] as? String else { return }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        }
    }
}
