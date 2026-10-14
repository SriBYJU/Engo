import UIKit
import MapKit
import CoreLocation
import ActiveLookSDK

/// Common ENGO 3 text canvas. Never silently chop off a line mid-word.
enum OpenLensCanvas {
    /// The 304x256 microdisplay supports three different hardware font sizes.
    /// Text uses the current size's wrapping and baseline spacing; no line is
    /// cut to a hard-coded global width.
    static func show(_ glasses: Glasses, title: String, lines: [String], size: OpenLensTextSize = .selected) {
        glasses.clear()
        let header = OpenLensText.sanitize(title).uppercased()
        // Keep the section label small and short so the readable body has room.
        let heading = OpenLensOrientation.origin(x: 42, y: 42)
        glasses.txt(x: heading.x, y: heading.y, rotation: OpenLensOrientation.rotation,
                    font: 0, color: 15, string: String(header.prefix(14)))
        for (index, line) in lines.prefix(size.linesPerPage).enumerated() {
            let at = OpenLensOrientation.origin(
                x: 42,
                y: size.firstLineY + index * size.lineSpacing
            )
            glasses.txt(x: at.x, y: at.y, rotation: OpenLensOrientation.rotation,
                        font: size.fontID, color: 15,
                        string: String(OpenLensText.sanitize(line).prefix(size.charactersPerLine)))
        }
    }
    static func show(_ glasses: Glasses, title: String, message: String, size: OpenLensTextSize = .selected) {
        show(glasses, title: title, lines: OpenLensText.pages(message, size: size)[0], size: size)
    }
}
/// Saved locally: no cloud or server needed.
enum OpenLensCardLibrary {
    static let key = "openlens.cards.v1"
    static let presets: [OpenLensCard] = [
        OpenLensCard(title: "Call me", body: "Please call me when you get a chance."),
        OpenLensCard(title: "Meeting reminder", body: "Stay focused. Listen first. Ask good questions."),
        OpenLensCard(title: "Practice cues", body: "Breathe. Relax your shoulders. Follow through."),
        OpenLensCard(title: "Presenting", body: "Slow down. Make eye contact. Pause after each point.")
    ]
    static func load() -> [OpenLensCard] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cards = try? JSONDecoder().decode([OpenLensCard].self, from: data) else { return [] }
        return cards
    }
    static func save(_ cards: [OpenLensCard]) {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

final class OpenLensCardsViewController: UITableViewController {
    private let glasses: Glasses
    private var saved = OpenLensCardLibrary.load()
    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Quick cards"
        tableView.backgroundColor = UIColor(red: 0.045, green: 0.066, blue: 0.075, alpha: 1)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCard))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "card")
        let label = UILabel(frame: CGRect(x: 18, y: 0, width: view.bounds.width - 36, height: 75))
        label.numberOfLines = 0
        label.text = "Tap a card to show it on your glasses. Longer cards open the page-by-page presenter. Cards stay on this iPhone."
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        tableView.tableHeaderView = label
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "STARTER CARDS" : "MY SAVED CARDS"
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? OpenLensCardLibrary.presets.count : saved.count
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let card = indexPath.section == 0 ? OpenLensCardLibrary.presets[indexPath.row] : saved[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "card", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()
        config.text = card.title
        config.secondaryText = String(card.body.prefix(90))
        config.textProperties.color = .label
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let card = indexPath.section == 0 ? OpenLensCardLibrary.presets[indexPath.row] : saved[indexPath.row]
        navigationController?.pushViewController(OpenLensPresenterViewController(glasses, title: card.title, body: card.body), animated: true)
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
            self?.editCard(at: indexPath.row)
            done(true)
        }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self = self, self.saved.indices.contains(indexPath.row) else { done(false); return }
            self.saved.remove(at: indexPath.row)
            OpenLensCardLibrary.save(self.saved)
            self.tableView.reloadData()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }
    @objc private func addCard() { prompt(existing: nil, index: nil) }
    private func editCard(at index: Int) {
        guard saved.indices.contains(index) else { return }
        prompt(existing: saved[index], index: index)
    }
    private func prompt(existing: OpenLensCard?, index: Int?) {
        let alert = UIAlertController(title: existing == nil ? "Save a quick card" : "Edit card", message: "Use a short title and a useful message.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title"; $0.text = existing?.title }
        alert.addTextField { $0.placeholder = "Text to display"; $0.text = existing?.body }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let title = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = (alert?.textFields?.last?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !body.isEmpty else { return }
            let card = OpenLensCard(id: existing?.id ?? UUID(), title: String(title.prefix(60)), body: String(body.prefix(2000)))
            if let index = index, self.saved.indices.contains(index) { self.saved[index] = card }
            else { self.saved.insert(card, at: 0) }
            OpenLensCardLibrary.save(self.saved)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}

final class OpenLensPresenterViewController: UIViewController {
    private let glasses: Glasses
    private let initialTitle: String
    private let initialBody: String
    private let editor = UITextView()
    private let textSizeControl = UISegmentedControl(items: OpenLensTextSize.allCases.map(\.name))
    private let sizeSummary = LensUI.label("", size: 13, color: LensUI.muted)
    private let pageInfo = UILabel()
    private let preview = UILabel()
    private let status = UILabel()
    private let back = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let auto = UIButton(type: .system)
    private var timer: Timer?
    private var pages: [[String]] = []
    private var current = 0

    init(_ glasses: Glasses, title: String = "Presenter", body: String = "") {
        self.glasses = glasses
        self.initialTitle = title
        self.initialBody = body
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Presenter"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("Presenter mode", detail: "Paste a speech, outline, or long note. Move through pages without losing the ending."))
        editor.text = initialBody
        editor.textColor = .white
        editor.backgroundColor = LensUI.card
        editor.font = .preferredFont(forTextStyle: .body)
        editor.layer.cornerRadius = 14
        editor.heightAnchor.constraint(equalToConstant: 160).isActive = true
        editor.accessibilityLabel = "Script to present"
        content.addArrangedSubview(editor)
        content.addArrangedSubview(LensUI.section("Size on glasses", detail: "Larger text is easier to read, and the script is split into more pages."))
        textSizeControl.selectedSegmentTintColor = LensUI.accent
        textSizeControl.selectedSegmentIndex = OpenLensTextSize.selected.rawValue
        textSizeControl.addTarget(self, action: #selector(textSizeChanged), for: .valueChanged)
        content.addArrangedSubview(textSizeControl)
        content.addArrangedSubview(sizeSummary)
        updateSizeSummary()
        content.addArrangedSubview(LensUI.button("Prepare pages", icon: "doc.text") { [weak self] in self?.prepare() })
        pageInfo.text = "No pages prepared"
        pageInfo.textColor = LensUI.accent
        pageInfo.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        content.addArrangedSubview(pageInfo)
        preview.numberOfLines = 0
        preview.textColor = .white
        preview.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        preview.textAlignment = .center
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true
        content.addArrangedSubview(LensUI.card(preview))
        let row = UIStackView(arrangedSubviews: [back, nextButton])
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        back.configuration = .filled()
        back.configuration?.title = "Previous"
        nextButton.configuration = .filled()
        nextButton.configuration?.title = "Next"
        back.addTarget(self, action: #selector(previousPage), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
        content.addArrangedSubview(row)
        auto.configuration = .bordered()
        auto.configuration?.title = "Auto-advance every 10s"
        auto.addTarget(self, action: #selector(toggleAuto), for: .touchUpInside)
        content.addArrangedSubview(auto)
        status.numberOfLines = 0
        status.textColor = LensUI.muted
        status.text = "Prepare pages before sending to ENGO 3."
        content.addArrangedSubview(status)
        if !initialBody.isEmpty { prepare() }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stopAuto() }
    private func updateSizeSummary() {
        let size = OpenLensTextSize.selected
        sizeSummary.text = "\(size.name) · \(size.fontHeight)px · \(size.charactersPerLine) characters/line · \(size.linesPerPage) lines/page"
    }
    @objc private func textSizeChanged() {
        guard let size = OpenLensTextSize(rawValue: textSizeControl.selectedSegmentIndex) else { return }
        OpenLensTextSize.selected = size
        updateSizeSummary()
        if !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { prepare() }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if textSizeControl.selectedSegmentIndex != OpenLensTextSize.selected.rawValue {
            textSizeControl.selectedSegmentIndex = OpenLensTextSize.selected.rawValue
            updateSizeSummary()
            if !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { prepare() }
        }
    }

    private func prepare() {
        stopAuto()
        editor.resignFirstResponder()
        let script = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { status.text = "Enter your notes first."; return }
        pages = OpenLensText.pages(script, size: .selected)
        current = 0
        render()
    }
    private func render() {
        guard pages.indices.contains(current) else { return }
        let lines = pages[current]
        let heading = "\(initialTitle.prefix(8)) \(current + 1)/\(pages.count)"
        OpenLensCanvas.show(glasses, title: heading, lines: lines)
        pageInfo.text = "PAGE \(current + 1) OF \(pages.count)"
        preview.text = lines.joined(separator: "\n")
        back.isEnabled = current > 0
        nextButton.isEnabled = current + 1 < pages.count
        status.text = "Page queued for your glasses."
    }
    @objc private func previousPage() { guard current > 0 else { return }; current -= 1; render() }
    @objc private func nextPage() {
        guard current + 1 < pages.count else { stopAuto(); return }
        current += 1
        render()
    }
    @objc private func toggleAuto() {
        if timer != nil { stopAuto(); return }
        if pages.isEmpty { prepare() }
        guard pages.count > 1 else { status.text = "Only one page to show."; return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.nextPage() }
        auto.configuration?.title = "Stop auto-advance"
        status.text = "Auto-advancing every 10 seconds while this screen is open."
    }
    private func stopAuto() {
        timer?.invalidate()
        timer = nil
        auto.configuration?.title = "Auto-advance every 10s"
    }
}

final class OpenLensFocusViewController: UIViewController {
    private let glasses: Glasses
    private let choices = UISegmentedControl(items: ["5 min", "15 min", "25 min"])
    private let digits = UILabel()
    private let state = UILabel()
    private let start = UIButton(type: .system)
    private var duration: TimeInterval = 5 * 60
    private var remaining: TimeInterval = 5 * 60
    private var end: Date?
    private var tickTimer: Timer?
    private var lastDisplayed = -1

    init(_ glasses: Glasses) { self.glasses = glasses; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Focus timer"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("Stay in the zone", detail: "A simple countdown in your ENGO 3. The timer continues while this screen is open."))
        choices.selectedSegmentIndex = 0
        choices.selectedSegmentTintColor = LensUI.accent
        choices.addTarget(self, action: #selector(setDuration), for: .valueChanged)
        content.addArrangedSubview(choices)
        digits.font = .monospacedDigitSystemFont(ofSize: 62, weight: .bold)
        digits.textAlignment = .center
        digits.textColor = .white
        digits.text = "05:00"
        content.addArrangedSubview(LensUI.card(digits))
        start.configuration = .filled()
        start.configuration?.title = "Start focus session"
        start.addTarget(self, action: #selector(startPause), for: .touchUpInside)
        content.addArrangedSubview(start)
        content.addArrangedSubview(LensUI.button("Reset timer", icon: "arrow.counterclockwise") { [weak self] in self?.reset() })
        content.addArrangedSubview(LensUI.button("Show current time", icon: "clock") { [weak self] in self?.showClock() })
        content.addArrangedSubview(LensUI.button("Clear glasses", icon: "xmark.circle") { [weak self] in self?.glasses.clear() })
        state.numberOfLines = 0
        state.textColor = LensUI.muted
        state.text = "Ready. Start to send the timer to your glasses."
        content.addArrangedSubview(state)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if end != nil { pause() }
        tickTimer?.invalidate()
    }
    @objc private func setDuration() {
        guard end == nil else { return }
        duration = [300.0, 900, 1500][choices.selectedSegmentIndex]
        remaining = duration
        digits.text = OpenLensText.countdown(remaining)
    }
    @objc private func startPause() {
        if end != nil { pause() }
        else {
            if remaining <= 0 { remaining = duration }
            end = Date().addingTimeInterval(remaining)
            start.configuration?.title = "Pause timer"
            choices.isEnabled = false
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            tick()
        }
    }
    private func pause() {
        if let end = end { remaining = max(0, end.timeIntervalSinceNow) }
        end = nil
        tickTimer?.invalidate()
        tickTimer = nil
        start.configuration?.title = "Resume timer"
        state.text = "Paused."
    }
    private func tick() {
        guard let end = end else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        digits.text = OpenLensText.countdown(remaining)
        let bucket = Int(remaining / 5)
        if bucket != lastDisplayed || remaining == 0 {
            OpenLensCanvas.show(glasses, title: "FOCUS SESSION", message: OpenLensText.countdown(remaining))
            lastDisplayed = bucket
        }
        if remaining == 0 {
            self.end = nil
            tickTimer?.invalidate()
            tickTimer = nil
            start.configuration?.title = "Start again"
            choices.isEnabled = true
            state.text = "Focus session complete."
            OpenLensCanvas.show(glasses, title: "FOCUS COMPLETE", message: "NICE WORK!")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else { state.text = "Running. Updated on glasses every ~5 seconds." }
    }
    private func reset() {
        tickTimer?.invalidate()
        tickTimer = nil
        end = nil
        choices.isEnabled = true
        remaining = duration
        lastDisplayed = -1
        digits.text = OpenLensText.countdown(remaining)
        start.configuration?.title = "Start focus session"
        state.text = "Reset."
    }
    private func showClock() {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        OpenLensCanvas.show(glasses, title: "CURRENT TIME", message: stamp)
        state.text = "Current phone time queued on glasses."
    }
}

/// Route instructions are manual preview steps, not live safety-critical guidance.
final class OpenLensRoutePreviewViewController: UIViewController, CLLocationManagerDelegate {
    private let glasses: Glasses
    private let locationManager = CLLocationManager()
    private let destination = UITextField()
    private let status = UILabel()
    private let instruction = UILabel()
    private let position = UILabel()
    private let previous = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private var pendingDestination: String?
    private var steps: [MKRoute.Step] = []
    private var stepIndex = 0
    private var lookup: MKLocalSearch?
    private var directions: MKDirections?

    init(_ glasses: Glasses) { self.glasses = glasses; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Walking route"
        locationManager.delegate = self
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("Walking route preview", detail: "Find walking directions and manually move through turns. Not live or safety-critical navigation."))
        destination.placeholder = "Where to?"
        destination.textColor = .white
        destination.backgroundColor = LensUI.card
        destination.layer.cornerRadius = 12
        destination.autocapitalizationType = .words
        destination.heightAnchor.constraint(equalToConstant: 52).isActive = true
        destination.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        destination.leftViewMode = .always
        content.addArrangedSubview(destination)
        content.addArrangedSubview(LensUI.button("Find walking route", icon: "figure.walk") { [weak self] in self?.findRoute() })
        position.textColor = LensUI.accent
        position.text = "No route yet"
        content.addArrangedSubview(position)
        instruction.textColor = .white
        instruction.font = .preferredFont(forTextStyle: .title3)
        instruction.numberOfLines = 0
        instruction.text = "Your next turn will appear here."
        instruction.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        content.addArrangedSubview(LensUI.card(instruction))
        let row = UIStackView(arrangedSubviews: [previous, nextButton])
        row.spacing = 12
        row.distribution = .fillEqually
        previous.configuration = .filled()
        previous.configuration?.title = "Previous turn"
        nextButton.configuration = .filled()
        nextButton.configuration?.title = "Next turn"
        previous.addTarget(self, action: #selector(previousStep), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextStep), for: .touchUpInside)
        content.addArrangedSubview(row)
        status.textColor = LensUI.muted
        status.numberOfLines = 0
        status.text = "Location is used only to calculate the route."
        content.addArrangedSubview(status)
        updateButtons()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lookup?.cancel()
        directions?.cancel()
    }
    private func updateButtons() {
        previous.isEnabled = stepIndex > 0
        nextButton.isEnabled = stepIndex + 1 < steps.count
    }
    private func findRoute() {
        destination.resignFirstResponder()
        guard let query = destination.text?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            status.text = "Type a destination first."
            return
        }
        pendingDestination = query
        steps = []
        updateButtons()
        guard CLLocationManager.locationServicesEnabled() else { status.text = "Enable Location Services in Settings."; return }
        let auth = locationManager.authorizationStatus
        switch auth {
        case .notDetermined:
            status.text = "Allow location to plan a walking route."
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            status.text = "Getting your current position…"
            locationManager.requestLocation()
        default: status.text = "Enable location permission for OpenLens in iPhone Settings."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        if (auth == .authorizedAlways || auth == .authorizedWhenInUse), pendingDestination != nil {
            manager.requestLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let here = locations.last, let query = pendingDestination else { return }
        pendingDestination = nil
        lookup?.cancel()
        directions?.cancel()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 25000, longitudinalMeters: 25000)
        status.text = "Finding destination…"
        lookup = MKLocalSearch(request: request)
        lookup?.start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let target = response?.mapItems.first else {
                    self.status.text = error?.localizedDescription ?? "Destination not found."
                    return
                }
                let plan = MKDirections.Request()
                plan.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
                plan.destination = target
                plan.transportType = .walking
                self.status.text = "Calculating walking directions…"
                self.directions = MKDirections(request: plan)
                self.directions?.calculate { [weak self] response, error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        guard let route = response?.routes.first else {
                            self.status.text = error?.localizedDescription ?? "No walking route found."
                            return
                        }
                        self.steps = route.steps.filter { !$0.instructions.isEmpty }
                        self.stepIndex = 0
                        if self.steps.isEmpty { self.status.text = "Route has no usable turns." }
                        else { self.showStep() }
                    }
                }
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status.text = "Location error: \(error.localizedDescription)"
    }
    private func showStep() {
        guard steps.indices.contains(stepIndex) else { return }
        let step = steps[stepIndex]
        position.text = "TURN \(stepIndex + 1) / \(steps.count)"
        instruction.text = step.instructions
        let meters = Int(step.distance.rounded())
        OpenLensCanvas.show(glasses, title: "WALK \(stepIndex + 1)/\(steps.count)", message: step.instructions)
        status.text = "Approx. \(meters) m for this step. Manually advance on your phone while stopped."
        updateButtons()
    }
    @objc private func previousStep() { guard stepIndex > 0 else { return }; stepIndex -= 1; showStep() }
    @objc private func nextStep() { guard stepIndex + 1 < steps.count else { return }; stepIndex += 1; showStep() }
}

final class OpenLensDiagnosticsViewController: UIViewController {
    private let glasses: Glasses
    private let report = UITextView()
    private var details = ""
    init(_ glasses: Glasses) { self.glasses = glasses; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Device diagnostics"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("Know your ENGO 3", detail: "Read the firmware and reported settings. No firmware changes are performed."))
        report.isEditable = false
        report.textColor = .white
        report.backgroundColor = LensUI.card
        report.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        report.layer.cornerRadius = 16
        report.heightAnchor.constraint(equalToConstant: 245).isActive = true
        content.addArrangedSubview(report)
        content.addArrangedSubview(LensUI.button("Refresh device details", icon: "arrow.clockwise") { [weak self] in self?.refresh() })
        content.addArrangedSubview(LensUI.button("Copy diagnostics", icon: "doc.on.doc") { [weak self] in
            UIPasteboard.general.string = self?.details
        })
        content.addArrangedSubview(LensUI.button("Display alignment test", icon: "viewfinder") { [weak self] in
            guard let self = self else { return }
            OpenLensCanvas.show(self.glasses, title: "ALIGNMENT TEST", message: "UP ^\nLEFT <   RIGHT >\nDOWN v")
        })
        content.addArrangedSubview(LensUI.button("Clear display", icon: "xmark.circle") { [weak self] in self?.glasses.clear() })
        refresh()
    }
    private func refresh() {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        details = "OPENLENS DIAGNOSTICS\nDevice: \(glasses.name)\nUpdated: \(stamp)\nReading…"
        report.text = details
        glasses.battery { [weak self] charge in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.append("Battery: \(charge)%")
            }
        }
        glasses.vers { [weak self] version in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.append("Firmware: \(version.firmwareVersion)\nSerial: \(version.serialNumber)")
            }
        }
        glasses.settings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.append("Brightness: \(settings.luma)/15\nAuto brightness: \(settings.brightnessAdjustmentEnabled)\nGesture detection: \(settings.gestureDetectionEnabled)\nShift: \(settings.xShift), \(settings.yShift)")
            }
        }
    }
    private func append(_ line: String) {
        details += "\n" + line
        report.text = details
    }
}
