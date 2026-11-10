// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import Foundation
import SwiftUI
import UserNotifications

/// Apps installed from Xcode with a free Apple ID carry a provisioning profile that is valid for
/// seven days; after that iOS refuses to open the app. Nothing inside an app can extend that
/// profile, so BookLand reads its own profile, shows how long is left, and reminds you before it
/// runs out. Reinstalling over the existing app from Xcode (never deleting it first) keeps the library.
@MainActor
final class IOSSigningMonitor: ObservableObject {
    @Published private(set) var expiry: Date?
    @Published private(set) var remindersEnabled: Bool
    @Published private(set) var notificationsDenied = false

    private static let remindersKey = "signingRemindersEnabled"
    private static let identifierPrefix = "bookland.expiry."

    init() {
        remindersEnabled = UserDefaults.standard.bool(forKey: Self.remindersKey)
        refresh()
    }

    /// True when this copy runs under an expiring development profile.
    var isLimited: Bool { expiry != nil }

    var timeLeft: TimeInterval? { expiry.map { $0.timeIntervalSinceNow } }

    /// Show the warning banner during the last three days.
    var shouldWarn: Bool {
        guard let left = timeLeft else { return false }
        return left < 3 * 24 * 3600
    }

    var timeLeftText: String {
        guard let left = timeLeft else { return "" }
        if left <= 0 { return "expired" }
        let hours = Int(left / 3600)
        if hours >= 48 { return "\(hours / 24) days" }
        if hours >= 24 { return "1 day \(hours - 24) h" }
        if hours >= 1 { return "\(hours) h" }
        return "under an hour"
    }

    func refresh() {
        expiry = Self.fakeExpiry() ?? Self.profileExpiry()
        if remindersEnabled { Task { await scheduleReminders() } }
    }

    func setReminders(_ enabled: Bool) async {
        if !enabled {
            remindersEnabled = false
            UserDefaults.standard.set(false, forKey: Self.remindersKey)
            clearReminders()
            return
        }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsDenied = !granted
        remindersEnabled = granted
        UserDefaults.standard.set(granted, forKey: Self.remindersKey)
        if granted { await scheduleReminders() }
    }

    private func clearReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.reminderIDs)
    }

    private static let reminderIDs = [identifierPrefix + "3d", identifierPrefix + "1d"]

    private func scheduleReminders() async {
        clearReminders()
        guard remindersEnabled, let expiry else { return }
        let plan: [(id: String, lead: TimeInterval, body: String)] = [
            (Self.identifierPrefix + "3d", 72 * 3600, "BookLand stops opening in about 3 days. Plug in your iPhone and press Run in Xcode when it suits you."),
            (Self.identifierPrefix + "1d", 24 * 3600, "BookLand stops opening tomorrow. Reinstall it from Xcode today; your library stays."),
        ]
        for item in plan {
            let fire = Self.daytime(expiry.addingTimeInterval(-item.lead))
            let delay = fire.timeIntervalSinceNow
            guard delay > 60, fire < expiry else { continue }
            let content = UNMutableNotificationContent()
            content.title = "BookLand needs a refresh"
            content.body = item.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// Nudge a reminder out of the night: anything before 09:00 moves to 09:00, after 21:00 to 20:00.
    private static func daytime(_ date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        if hour < 9 { return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date }
        if hour >= 21 { return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date }
        return date
    }

    /// Reads ExpirationDate from the embedded provisioning profile (absent in the Simulator).
    private static func profileExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>"),
              start.lowerBound < end.upperBound,
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Launch with `-fakeExpiryDays 1.5` to preview the warning UI in the Simulator.
    private static func fakeExpiry() -> Date? {
        let days = UserDefaults.standard.double(forKey: "fakeExpiryDays")
        return days > 0 ? Date().addingTimeInterval(days * 24 * 3600) : nil
    }
}
