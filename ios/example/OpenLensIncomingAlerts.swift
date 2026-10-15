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


/// Explicit alert controls and test harness. Shortcuts must be configured by
/// the user; OpenLens cannot automatically subscribe to another app's inbox.
final class OpenLensMessageAlertsViewController: UIViewController {
    private let glasses: Glasses
    private let enabled = UISwitch()
    private let showBody = UISwitch()
    private let status = LensUI.label("", size: 13, color: LensUI.muted)
    private let latest = LensUI.label("", size: 14)
    private let recentStack = UIStackView()

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Message Alerts"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("Notifications on your glasses",
            detail: "Optional, powered by Shortcuts automations that YOU create. OpenLens can't read all incoming iMessage, WhatsApp or other apps' notifications by itself."))

        enabled.onTintColor = LensUI.accent
        enabled.isOn = OpenLensIncomingAlertStore.enabled
        enabled.addTarget(self, action: #selector(toggleAlerts), for: .valueChanged)
        let enableRow = UIStackView(arrangedSubviews: [
            LensUI.label("Allow incoming Shortcut alerts", size: 15), enabled
        ])
        enableRow.distribution = .equalSpacing
        enableRow.alignment = .center
        content.addArrangedSubview(LensUI.card(enableRow))

        showBody.onTintColor = LensUI.accent
        showBody.isOn = OpenLensIncomingAlertStore.showContent
        showBody.isEnabled = enabled.isOn
        showBody.addTarget(self, action: #selector(toggleContent), for: .valueChanged)
        let contentRow = UIStackView(arrangedSubviews: [
            LensUI.label("Show message content on glasses", size: 14), showBody
        ])
        contentRow.alignment = .center
        contentRow.distribution = .equalSpacing
        content.addArrangedSubview(LensUI.card(contentRow))
        content.addArrangedSubview(LensUI.label(
            "Privacy default: sender only. Turn on message content ONLY if you want private messages visible through your glasses. A notification can remain saved locally until you delete it.",
            size: 12, color: LensUI.muted))

        content.addArrangedSubview(LensUI.button("Send a test notification to my glasses",
            icon: "bell.badge") { [weak self] in self?.sendTest() })
        status.text = "The glasses need to be connected with OpenLens active. Shortcuts may bring OpenLens to the foreground."
        content.addArrangedSubview(status)

        content.addArrangedSubview(LensUI.section("Set up an iPhone automation",
            detail: "This step is required for real incoming messages. OpenLens cannot create a Shortcuts automation silently."))
        content.addArrangedSubview(LensUI.label(
            "1. Open Apple's Shortcuts app → Automation → +.\n" +
            "2. Choose Message (received), select the sender(s), and choose Run Immediately if offered.\n" +
            "3. Add the OpenLens action “Forward Message Alert to OpenLens.”\n" +
            "4. Pass the trigger's Sender and Message Content fields to the action. Set Source App to “Messages.”\n" +
            "5. Save, then ask someone to text you. The alert can be shown when OpenLens is active and the glasses are connected.\n\n" +
            "For other apps: iOS versions with a Notification trigger may let you choose an app, for example WhatsApp. Forward only the notification details exposed by Shortcuts.",
            size: 14, color: .white))
        content.addArrangedSubview(LensUI.button("Open Shortcuts",
            icon: "square.stack.3d.up") {
                if let url = URL(string: "shortcuts://") {
                    UIApplication.shared.open(url)
                }
            })
        content.addArrangedSubview(LensUI.label(
            "Important: These automations can launch OpenLens, but iOS may suspend it or disconnect BLE when it is in the background. Alerts are not guaranteed to appear automatically on the glasses with the app closed. Not all notification triggers provide full message bodies.",
            size: 12, color: LensUI.muted))

        content.addArrangedSubview(LensUI.section("Recent alerts", detail: "Last 12 forwarded alerts stored locally. Tap one to read its available text."))
        latest.text = "No alerts forwarded yet."
        content.addArrangedSubview(latest)
        recentStack.axis = .vertical
        recentStack.spacing = 9
        content.addArrangedSubview(recentStack)
        content.addArrangedSubview(LensUI.button("Delete all forwarded alerts",
            icon: "trash") { [weak self] in self?.clearConfirmation() })
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    @objc private func toggleAlerts() {
        OpenLensIncomingAlertStore.enabled = enabled.isOn
        showBody.isEnabled = enabled.isOn
        status.text = enabled.isOn
            ? "Alerts enabled. Set up an iPhone Shortcuts automation to forward selected messages."
            : "Alerts disabled. No new message data will be accepted. Saved alerts remain until deleted."
    }

    @objc private func toggleContent() {
        OpenLensIncomingAlertStore.showContent = showBody.isOn
        status.text = showBody.isOn
            ? "Full message previews enabled; use only when comfortable showing private text on the glasses."
            : "Future alerts will contain sender only; any older saved previews remain until deleted."
    }

    private func sendTest() {
        guard enabled.isOn else {
            status.text = "First enable incoming Shortcut alerts."
            return
        }
        guard let record = OpenLensIncomingAlertStore.append(
            sender: "Demo Contact", source: "Messages",
            message: "Hey! OpenLens test alert is working.") else {
            status.text = "Could not create a test alert."
            return
        }
        display(record)
        OpenLensIncomingAlertStore.markDisplayed(record)
        status.text = "Test alert queued for ENGO 3. This tests the display only, not background Shortcuts delivery."
        refresh()
    }

    private func display(_ alert: OpenLensIncomingMessage) {
        navigationController?.pushViewController(OpenLensPresenterViewController(
            glasses, title: "MESSAGE ALERT", body: alert.glassesText), animated: true)
    }

    private func refresh() {
        let records = OpenLensIncomingAlertStore.load()
        latest.text = records.isEmpty ? "No alerts forwarded yet." :
            "Latest: \(records[0].source) from \(records[0].sender)"
        for view in recentStack.arrangedSubviews {
            recentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for record in records {
            recentStack.addArrangedSubview(LensUI.button(
                "\(record.source): \(record.sender)", icon: "message.badge") { [weak self] in
                    guard let self = self else { return }
                    self.display(record)
                    OpenLensIncomingAlertStore.markDisplayed(record)
                })
        }
    }

    private func clearConfirmation() {
        let prompt = UIAlertController(title: "Delete all OpenLens message alerts?",
            message: "This deletes only the locally saved alert copies. It will not delete actual Messages or WhatsApp conversations.",
            preferredStyle: .alert)
        prompt.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        prompt.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            OpenLensIncomingAlertStore.clear()
            self?.refresh()
            self?.status.text = "OpenLens alert history cleared."
        })
        present(prompt, animated: true)
    }
}
