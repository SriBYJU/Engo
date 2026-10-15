import Foundation
import UIKit
import AppIntents
import ActiveLookSDK

/// A user-enabled bridge between Shortcuts automation events and OpenLens.
/// It cannot directly read messages or other apps' system notifications.
enum OpenLensIncomingAlertStore {
    static let notificationName = Notification.Name("openlens.message-alert.received")
    private static let alertsKey = "openlens.message-alerts.history"
    private static let enabledKey = "openlens.message-alerts.enabled"
    private static let contentKey = "openlens.message-alerts.show-content"
    private static let displayedIDKey = "openlens.message-alerts.last-displayed"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var showContent: Bool {
        get { UserDefaults.standard.bool(forKey: contentKey) }
        set { UserDefaults.standard.set(newValue, forKey: contentKey) }
    }
    static func load() -> [OpenLensIncomingMessage] {
        guard let data = UserDefaults.standard.data(forKey: alertsKey),
              let result = try? JSONDecoder().decode([OpenLensIncomingMessage].self, from: data)
        else { return [] }
        return OpenLensIncomingMessage.recent(result)
    }
    static func append(sender: String, source: String, message: String) -> OpenLensIncomingMessage? {
        guard enabled,
              let record = OpenLensIncomingMessage(sender: sender, source: source,
                                                  body: message, retainBody: showContent) else {
            return nil
        }
        var history = load()
        history.insert(record, at: 0)
        guard let bytes = try? JSONEncoder().encode(OpenLensIncomingMessage.recent(history)) else {
            return nil
        }
        UserDefaults.standard.set(bytes, forKey: alertsKey)
        NotificationCenter.default.post(name: notificationName, object: nil)
        return record
    }
    static func nextUndisplayed() -> OpenLensIncomingMessage? {
        guard enabled, let latest = load().first else { return nil }
        let shown = UserDefaults.standard.string(forKey: displayedIDKey)
        return latest.id.uuidString == shown ? nil : latest
    }
    static func markDisplayed(_ alert: OpenLensIncomingMessage) {
        UserDefaults.standard.set(alert.id.uuidString, forKey: displayedIDKey)
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: alertsKey)
        UserDefaults.standard.removeObject(forKey: displayedIDKey)
    }
}

@available(iOS 16.0, *)
struct OpenLensForwardAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Forward Message Alert to OpenLens"
    static var description = IntentDescription(
        "Receive a message or app notification chosen in Shortcuts and show its sender on your connected ENGO 3."
    )
    // Bluetooth HUD updates are not a supported headless background action.
    // Bring OpenLens forward; once glasses connect the pending alert can appear.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Sender")
    var sender: String

    @Parameter(title: "Message Content")
    var message: String

    @Parameter(title: "Source App")
    var source: String

    init() {}
    init(sender: String, message: String, source: String) {
        self.sender = sender
        self.message = message
        self.source = source
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Without in-app opt-in, the action saves nothing and does not display.
        _ = OpenLensIncomingAlertStore.append(
            sender: sender, source: source, message: message)
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenLensMessageAlertAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLensForwardAlertIntent(),
            phrases: [
                "Forward a message alert to \(.applicationName)",
                "Show an alert in \(.applicationName)"
            ],
            shortTitle: "Message Alert",
            systemImageName: "message.badge"
        )
    }
}
