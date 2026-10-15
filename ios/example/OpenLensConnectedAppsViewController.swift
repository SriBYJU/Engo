import UIKit
import ActiveLookSDK
import EventKit
import Contacts
import ContactsUI

/// Everything here uses Apple's documented permissions or explicit user
/// sharing. iOS does not let an ordinary app inspect iMessage/WhatsApp inboxes
/// or intercept other apps' notifications.
final class OpenLensConnectedAppsViewController: UIViewController, CNContactPickerDelegate {
    private let glasses: Glasses
    private let calendarStatus = LensUI.label("Not connected yet", size: 13, color: LensUI.muted)
    private let reminderStatus = LensUI.label("Not connected yet", size: 13, color: LensUI.muted)
    private let contactStatus = LensUI.label("Select a contact to preview it", size: 13, color: LensUI.muted)
    private let contactButton = UIButton(type: .system)
    private var selectedContactText: String?

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Connected Apps"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.label("Your iPhone, in view.", size: 28, weight: .bold))
        content.addArrangedSubview(LensUI.label(
            "Choose what OpenLens can read. Nothing is sent to the glasses until you tap to display it.",
            size: 14, color: LensUI.muted))

        content.addArrangedSubview(LensUI.section("Live iPhone data",
            detail: "Calendar and Reminders update from accounts already synced to your iPhone. Each needs your permission."))
        content.addArrangedSubview(LensUI.button("Calendar  ·  Upcoming events",
            icon: "calendar") { [weak self] in self?.openAgenda(.calendar) })
        content.addArrangedSubview(calendarStatus)
        content.addArrangedSubview(LensUI.button("Reminders  ·  To-do list",
            icon: "checklist") { [weak self] in self?.openAgenda(.reminders) })
        content.addArrangedSubview(reminderStatus)

        content.addArrangedSubview(LensUI.section("Messages, WhatsApp, Mail and Notes",
            detail: "iOS does not let OpenLens automatically read chats or inbox notifications. Copy or paste only the text you choose."))
        content.addArrangedSubview(LensUI.button("Shared Clips  ·  Paste from any app",
            icon: "doc.on.clipboard") { [weak self] in
                guard let self = self else { return }
                self.open(OpenLensSharedClipsViewController(self.glasses))
            })
        content.addArrangedSubview(LensUI.label(
            "On your iPhone: open Messages, WhatsApp, Gmail, Mail, Notes or Safari → select text → Copy → return to OpenLens → Shared Clips → Paste. Preview it and send it to your glasses. Saving is optional.",
            size: 13, color: LensUI.muted))

        content.addArrangedSubview(LensUI.section("Contacts", detail: "Select a single contact. OpenLens doesn't import your entire address book."))
        content.addArrangedSubview(LensUI.button("Choose a contact",
            icon: "person.crop.circle") { [weak self] in self?.chooseContact() })
        content.addArrangedSubview(contactStatus)
        contactButton.configuration = .filled()
        contactButton.configuration?.title = "Show selected contact on glasses"
        contactButton.configuration?.image = UIImage(systemName: "eyeglasses")
        contactButton.configuration?.imagePadding = 10
        contactButton.addTarget(self, action: #selector(displayContact), for: .touchUpInside)
        contactButton.isEnabled = false
        content.addArrangedSubview(contactButton)

        content.addArrangedSubview(LensUI.section("Open an app",
            detail: "Opening Messages doesn't grant OpenLens access to your inbox. To display a message, copy its text first."))
        content.addArrangedSubview(LensUI.button("Open Apple Messages",
            icon: "message.fill") { [weak self] in
                guard let self = self else { return }
                guard let url = URL(string: "sms:") else { return }
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success {
                        DispatchQueue.main.async { self.showInfo("Messages could not be opened on this device.") }
                    }
                }
            })
        content.addArrangedSubview(LensUI.label(
            "Calendar/Reminders: read-only inside OpenLens; editing stays in Apple's apps. Contacts and clips are displayed only after you select them. No automatic message mirroring or background chat monitoring.",
            size: 12, color: LensUI.muted))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        calendarStatus.text = permissionLabel(for: .event, service: "Calendar")
        reminderStatus.text = permissionLabel(for: .reminder, service: "Reminders")
    }
    private func permissionLabel(for type: EKEntityType, service: String) -> String {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(iOS 17.0, *) {
            switch status {
            case .fullAccess: return "● \(service) connected • tap to see recent updates."
            case .writeOnly: return "Only write access granted; reading requires full access."
            case .denied, .restricted: return "Access denied • change in iPhone Settings if desired."
            default: return "Not connected • permission is requested only when you open it."
            }
        } else {
            switch status {
            case .authorized: return "● \(service) connected • tap to view."
            case .denied, .restricted: return "Access denied • change in iPhone Settings if desired."
            default: return "Not connected • tap to request permission."
            }
        }
    }
    private func openAgenda(_ kind: OpenLensAgendaViewController.Kind) {
        open(OpenLensAgendaViewController(glasses, kind: kind))
    }
    private func open(_ screen: UIViewController) {
        screen.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(screen, animated: true)
    }
    private func chooseContact() {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        present(picker, animated: true)
    }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Selected contact"
        let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        let email = contact.emailAddresses.first?.value as String? ?? ""
        let info = [name, phone, email].filter { !$0.isEmpty }.joined(separator: "\n")
        selectedContactText = info
        contactStatus.text = "Selected: \(name). Only this contact is accessible to OpenLens."
        contactButton.isEnabled = !info.isEmpty
    }
    @objc private func displayContact() {
        guard let content = selectedContactText else { return }
        open(OpenLensPresenterViewController(glasses, title: "CONTACT", body: content))
    }
    private func showInfo(_ message: String) {
        let alert = UIAlertController(title: "Connected Apps", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// Reads upcoming events and incomplete reminders from the user's existing
/// system data after an explicit Apple authorization prompt.
final class OpenLensAgendaViewController: UITableViewController {
    enum Kind { case calendar, reminders }
    private let glasses: Glasses
    private let kind: Kind
    private let eventStore = EKEventStore()
    private var events: [EKEvent] = []
    private var reminders: [EKReminder] = []
    private var generation = 0
    private var descriptionText = ""
    private var permissionButton: UIBarButtonItem?

    init(_ glasses: Glasses, kind: Kind) {
        self.glasses = glasses
        self.kind = kind
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    private var entity: EKEntityType { kind == .calendar ? .event : .reminder }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = kind == .calendar ? "Calendar" : "Reminders"
        tableView.backgroundColor = LensUI.bg
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "agenda")
        let header = UILabel(frame: CGRect(x: 15, y: 0, width: view.bounds.width - 30, height: 104))
        header.text = kind == .calendar
            ? "Your next 7 days of iPhone calendar events. Tap an event to read its details on ENGO 3. OpenLens never modifies events."
            : "Incomplete tasks from your iPhone Reminders lists. Tap a task to display the full title and due date. Nothing is marked complete."
        header.font = .preferredFont(forTextStyle: .footnote)
        header.textColor = .secondaryLabel
        header.numberOfLines = 0
        tableView.tableHeaderView = header
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Connect", style: .plain, target: self, action: #selector(connectOrRefresh))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshIfAuthorized), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshIfAuthorized),
            name: .EKEventStoreChanged, object: nil)
        showCurrentStatus()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshIfAuthorized()
    }
    private var hasPermission: Bool {
        let status = EKEventStore.authorizationStatus(for: entity)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }
    private func showCurrentStatus() {
        navigationItem.rightBarButtonItem?.title = hasPermission ? "Refresh" : "Connect"
        if hasPermission {
            descriptionText = "Fetching \(kind == .calendar ? "calendar events" : "reminders")…"
        } else {
            descriptionText = "To read \(kind == .calendar ? "calendar events" : "reminders"), tap Connect and grant access."
        }
        tableView.reloadData()
    }
    @objc private func connectOrRefresh() {
        guard !hasPermission else { fetch() ; return }
        let completion: (Bool, Error?) -> Void = { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted { self.fetch() }
                else {
                    self.descriptionText = error?.localizedDescription ??
                        "Permission not granted. Allow it in Settings → Privacy & Security."
                    self.tableView.reloadData()
                }
            }
        }
        if #available(iOS 17.0, *) {
            if kind == .calendar { eventStore.requestFullAccessToEvents(completion: completion) }
            else { eventStore.requestFullAccessToReminders(completion: completion) }
        } else {
            eventStore.requestAccess(to: entity, completion: completion)
        }
    }
    @objc private func refreshIfAuthorized() {
        if hasPermission { fetch() }
        else { showCurrentStatus(); refreshControl?.endRefreshing() }
    }
    private func fetch() {
        guard hasPermission else { showCurrentStatus(); return }
        generation += 1
        let current = generation
        navigationItem.rightBarButtonItem?.title = "Refresh"
        descriptionText = "Loading from \(kind == .calendar ? "Calendar" : "Reminders")…"
        tableView.reloadData()

        if kind == .calendar {
            let beginning = Date()
            let end = Calendar.current.date(byAdding: .day, value: 7, to: beginning) ?? beginning.addingTimeInterval(7 * 86400)
            let predicate = eventStore.predicateForEvents(withStart: beginning, end: end, calendars: nil)
            events = Array(eventStore.events(matching: predicate)
                .sorted(by: { $0.startDate < $1.startDate }).prefix(40))
            reminders = []
            descriptionText = events.isEmpty ? "No events found in the next 7 days." : ""
            refreshControl?.endRefreshing()
            tableView.reloadData()
        } else {
            let predicate = eventStore.predicateForReminders(in: nil)
            eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == current else { return }
                    let active = (reminders ?? []).filter { !$0.isCompleted }
                    self.reminders = Array(active.sorted(by: { x, y in
                        let first = x.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
                        let second = y.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
                        return first < second
                    }).prefix(50))
                    self.events = []
                    self.descriptionText = self.reminders.isEmpty
                        ? "No incomplete reminders found." : ""
                    self.refreshControl?.endRefreshing()
                    self.tableView.reloadData()
                }
            }
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, kind == .calendar ? events.count : reminders.count)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "agenda", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()
        config.textProperties.color = .label
        config.secondaryTextProperties.color = .secondaryLabel
        config.textProperties.numberOfLines = 2
        config.secondaryTextProperties.numberOfLines = 2
        if kind == .calendar && events.indices.contains(indexPath.row) {
            let event = events[indexPath.row]
            config.text = event.title ?? "Untitled event"
            config.secondaryText = DateFormatter.localizedString(
                from: event.startDate, dateStyle: .medium, timeStyle: .short)
            cell.accessoryType = .disclosureIndicator
        } else if kind == .reminders && reminders.indices.contains(indexPath.row) {
            let reminder = reminders[indexPath.row]
            config.text = reminder.title ?? "Untitled task"
            if let components = reminder.dueDateComponents,
               let date = Calendar.current.date(from: components) {
                config.secondaryText = "Due: " + DateFormatter.localizedString(
                    from: date, dateStyle: .medium, timeStyle: .short)
            } else { config.secondaryText = "No due date" }
            cell.accessoryType = .disclosureIndicator
        } else {
            config.text = descriptionText.isEmpty ? "No items to display." : descriptionText
            config.secondaryText = "You control what is shown on the glasses."
            cell.accessoryType = .none
        }
        cell.contentConfiguration = config
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        var body = ""
        if kind == .calendar && events.indices.contains(indexPath.row) {
            let event = events[indexPath.row]
            let dateRange = event.isAllDay
                ? DateFormatter.localizedString(from: event.startDate, dateStyle: .full, timeStyle: .none)
                : DateFormatter.localizedString(from: event.startDate, dateStyle: .full, timeStyle: .short)
            body = [
                event.title ?? "Calendar event",
                dateRange,
                event.location.map { "Location: " + $0 } ?? ""
            ].filter { !$0.isEmpty }.joined(separator: "\n")
        } else if kind == .reminders && reminders.indices.contains(indexPath.row) {
            let item = reminders[indexPath.row]
            body = item.title ?? "Reminder"
            if let comps = item.dueDateComponents,
               let due = Calendar.current.date(from: comps) {
                body += "\nDue " + DateFormatter.localizedString(from: due, dateStyle: .full, timeStyle: .short)
            }
        }
        guard !body.isEmpty else { return }
        navigationController?.pushViewController(
            OpenLensPresenterViewController(glasses, title: kind == .calendar ? "EVENT" : "REMINDER", body: body),
            animated: true)
    }
}

/// The clipboard is read only after a button tap. Saved clips are optional,
/// stored locally, and never automatically uploaded to any AI service.
private enum OpenLensSharedClipLibrary {
    private static let key = "openlens.shared-clips.v1"
    static func load() -> [OpenLensSharedClip] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([OpenLensSharedClip].self, from: data)
        else { return [] }
        return OpenLensSharedClip.limited(items)
    }
    static func save(_ clips: [OpenLensSharedClip]) {
        let bounded = OpenLensSharedClip.limited(clips)
        guard let bytes = try? JSONEncoder().encode(bounded) else { return }
        UserDefaults.standard.set(bytes, forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

final class OpenLensSharedClipsViewController: UIViewController, UITextViewDelegate {
    private let glasses: Glasses
    private let editor = UITextView()
    private let sourceButton = UIButton(type: .system)
    private let status = LensUI.label("", size: 13, color: LensUI.muted)
    private let savedStack = UIStackView()
    private let showButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private var source = "Messages"

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Shared Clips"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("From any app → to ENGO 3",
            detail: "In Messages, WhatsApp, Gmail, Mail, Notes or Safari, select text and tap Copy. Come back here and tap Paste clipboard. There is no automatic inbox access."))

        sourceButton.configuration = .bordered()
        sourceButton.configuration?.title = "Source: Messages ▾"
        sourceButton.configuration?.image = UIImage(systemName: "square.on.square")
        sourceButton.configuration?.imagePadding = 8
        sourceButton.menu = UIMenu(title: "Where did this text come from?",
            children: OpenLensSharedClip.sourceChoices.map { option in
                UIAction(title: option) { [weak self] _ in
                    guard let self = self else { return }
                    self.source = option
                    self.sourceButton.configuration?.title = "Source: \(option) ▾"
                }
            })
        sourceButton.showsMenuAsPrimaryAction = true
        content.addArrangedSubview(sourceButton)
        content.addArrangedSubview(LensUI.button("Paste clipboard (only when tapped)",
            icon: "doc.on.clipboard.fill") { [weak self] in self?.paste() })

        editor.delegate = self
        editor.textColor = .white
        editor.font = .preferredFont(forTextStyle: .body)
        editor.backgroundColor = LensUI.card
        editor.layer.cornerRadius = 16
        editor.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        editor.heightAnchor.constraint(equalToConstant: 175).isActive = true
        editor.accessibilityLabel = "Text copied from another app; editable before sending"
        content.addArrangedSubview(editor)

        showButton.configuration = .filled()
        showButton.configuration?.title = "Show complete text on glasses"
        showButton.configuration?.image = UIImage(systemName: "eyeglasses")
        showButton.configuration?.imagePadding = 9
        showButton.addTarget(self, action: #selector(showClip), for: .touchUpInside)
        content.addArrangedSubview(showButton)
        saveButton.configuration = .bordered()
        saveButton.configuration?.title = "Save this clip on iPhone"
        saveButton.configuration?.image = UIImage(systemName: "bookmark")
        saveButton.addTarget(self, action: #selector(saveClip), for: .touchUpInside)
        content.addArrangedSubview(saveButton)
        status.text = "Text is not saved unless you tap Save. Do not paste passwords or one-time codes."
        content.addArrangedSubview(status)
        content.addArrangedSubview(LensUI.section("My saved clips",
            detail: "Saved only on this iPhone, not synced to the cloud by OpenLens. Tap a clip to read it on your glasses. Delete anytime."))
        savedStack.axis = .vertical
        savedStack.spacing = 10
        content.addArrangedSubview(savedStack)
        content.addArrangedSubview(LensUI.button("Delete all saved clips",
            icon: "trash") { [weak self] in self?.confirmClear() })
        updateEditorButtons()
        updateSavedClips()
    }

    func textViewDidChange(_ textView: UITextView) { updateEditorButtons() }
    private func updateEditorButtons() {
        let hasText = !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showButton.isEnabled = hasText
        saveButton.isEnabled = hasText
    }
    private func paste() {
        // Explicit tap is required; system may also show its Paste permission.
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            status.text = "Clipboard contains no text. Copy a message or note first."
            return
        }
        if text.count > OpenLensSharedClip.maxCharacters {
            status.text = "Pasted \(text.count) characters. The first 4,000 can be saved. The full pasted text can still be displayed."
        } else {
            status.text = "Pasted text from clipboard. Review it before sending."
        }
        editor.text = text
        updateEditorButtons()
    }
    @objc private func showClip() {
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        editor.resignFirstResponder()
        navigationController?.pushViewController(
            OpenLensPresenterViewController(glasses, title: source.uppercased(), body: text),
            animated: true)
    }
    @objc private func saveClip() {
        guard let clip = OpenLensSharedClip(source: source, text: editor.text) else { return }
        var all = OpenLensSharedClipLibrary.load()
        all.insert(clip, at: 0)
        OpenLensSharedClipLibrary.save(all)
        updateSavedClips()
        status.text = "Saved on this iPhone. Nothing was shared with OpenLens AI."
    }
    private func updateSavedClips() {
        for view in savedStack.arrangedSubviews {
            savedStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let clips = OpenLensSharedClipLibrary.load()
        if clips.isEmpty {
            savedStack.addArrangedSubview(LensUI.label(
                "No saved clips. Clipboard imports are never auto-saved.",
                size: 14, color: LensUI.muted))
        }
        for clip in clips {
            let snippet = String(clip.body.replacingOccurrences(of: "\n", with: " ").prefix(34))
            let open = LensUI.button("\(clip.source): \(snippet)",
                icon: "text.bubble") { [weak self] in
                    guard let self = self else { return }
                    self.navigationController?.pushViewController(
                        OpenLensPresenterViewController(self.glasses,
                            title: clip.source.uppercased(), body: clip.body),
                        animated: true)
                }
            let delete = UIButton(type: .system)
            delete.configuration = .bordered()
            delete.configuration?.image = UIImage(systemName: "trash")
            delete.accessibilityLabel = "Delete clip from \(clip.source)"
            delete.addAction(UIAction { [weak self] _ in self?.deleteClip(clip.id) }, for: .touchUpInside)
            delete.widthAnchor.constraint(equalToConstant: 55).isActive = true
            let row = UIStackView(arrangedSubviews: [open, delete])
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fill
            savedStack.addArrangedSubview(row)
        }
    }
    private func deleteClip(_ id: UUID) {
        var clips = OpenLensSharedClipLibrary.load()
        clips.removeAll(where: { $0.id == id })
        OpenLensSharedClipLibrary.save(clips)
        updateSavedClips()
        status.text = "Saved clip deleted."
    }
    private func confirmClear() {
        let alert = UIAlertController(title: "Delete all saved clips?",
            message: "This permanently removes only OpenLens's locally saved clips. Your original messages and notes remain untouched.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete clips", style: .destructive) { [weak self] _ in
            OpenLensSharedClipLibrary.clear()
            self?.updateSavedClips()
            self?.status.text = "Saved clips cleared from this iPhone."
        })
        present(alert, animated: true)
    }
}
