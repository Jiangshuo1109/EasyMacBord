import Foundation
import UserNotifications

@MainActor
protocol WaterReminderScheduling: AnyObject {
    func schedule(everyMinutes minutes: Int) async -> ActionExecutionResult
}

@MainActor
final class WaterReminderScheduler: WaterReminderScheduling {
    static let notificationIdentifier = "com.easymacbord.water-reminder"
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func schedule(everyMinutes minutes: Int) async -> ActionExecutionResult {
        guard (1...1_440).contains(minutes) else {
            return .failed("提醒间隔需在 1 到 1440 分钟之间")
        }

        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            do {
                guard try await notificationCenter.requestAuthorization(options: [.alert, .sound]) else {
                    return .failed("未获通知权限")
                }
            } catch {
                return .failed("无法请求通知权限")
            }
        }

        let content = UNMutableNotificationContent()
        content.title = "喝水提醒"
        content.body = "休息一下，补充些水分。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: true)
        )
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        do {
            try await notificationCenter.add(request)
            return .succeeded
        } catch {
            return .failed("无法安排喝水提醒")
        }
    }
}
