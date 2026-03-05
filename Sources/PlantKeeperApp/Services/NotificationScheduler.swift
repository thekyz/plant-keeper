import Foundation
import UserNotifications
import PlantKeeperCore

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async
    func scheduleDailyDigest(hour: Int, minute: Int) async
    func refreshUrgencyNotifications(plants: [PlantRecord], now: Date) async
}

struct NotificationScheduler: NotificationScheduling {
    private var canUseUserNotifications: Bool {
        #if os(iOS)
        return true
        #else
        // `swift run` on macOS launches from `.build/...` (not an app bundle),
        // and UNUserNotificationCenter can crash with NSInternalInconsistencyException there.
        let bundleURL = Bundle.main.bundleURL
        let hasAppBundle = bundleURL.pathExtension.lowercased() == "app"
        let hasBundleID = Bundle.main.bundleIdentifier != nil
        return hasAppBundle && hasBundleID
        #endif
    }

    func requestAuthorizationIfNeeded() async {
        guard canUseUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func scheduleDailyDigest(hour: Int, minute: Int) async {
        guard canUseUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Plant check reminder"
        content.body = "Open Plant Keeper to review today's urgent plants."

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-digest", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func refreshUrgencyNotifications(plants: [PlantRecord], now: Date) async {
        guard canUseUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        let overdue = plants.filter { min($0.nextWaterDueAt, $0.nextCheckDueAt) <= now }

        guard !overdue.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: ["urgent-overdue"])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Plants need attention"
        content.body = "\(overdue.count) plant(s) are overdue."

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "urgent-overdue", content: content, trigger: trigger)
        try? await center.add(request)
    }
}
