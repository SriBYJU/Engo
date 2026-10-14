import UIKit
import MapKit
import CoreLocation
import ActiveLookSDK

/// Bitmapped text shares the exact 1-bit image transport used by Photos.
/// The SDK internally rotates image pixels 180° to compensate for the optics.
/// It must NOT also use native txt() rotation/anchor coordinates.
enum OpenLensBitmapSettings {
    private static let flipKey = "openlens.bitmap.rotate180"
    private static let xKey = "openlens.bitmap.offsetX"
    private static let yKey = "openlens.bitmap.offsetY"
    static var rotated: Bool {
        get { UserDefaults.standard.bool(forKey: flipKey) }
        set { UserDefaults.standard.set(newValue, forKey: flipKey) }
    }
    static var offsetX: Int {
        get { UserDefaults.standard.integer(forKey: xKey) }
        set { UserDefaults.standard.set(max(-24, min(24, newValue)), forKey: xKey) }
    }
    static var offsetY: Int {
        get { UserDefaults.standard.integer(forKey: yKey) }
        set { UserDefaults.standard.set(max(-24, min(24, newValue)), forKey: yKey) }
    }
}

/// ActiveLookSDK v4.5.5 hard-asserts that a streamed UIImage's CGImage
/// uses the RGB color-space model. UIGraphicsImageRenderer can produce
/// an extended/monochrome CGImage on some devices, so explicitly normalize.
enum OpenLensRGBImage {
    static func normalize(_ source: UIImage) -> UIImage? {
        guard let original = source.cgImage else { return nil }
        let width = original.width
        let height = original.height
        guard width > 0 && height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let flags = CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: flags) else { return nil }
        context.interpolationQuality = .none
        // Convert raster data into a standard RGBA8 device-RGB backed image.
        context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rgb = context.makeImage(),
              rgb.colorSpace?.model == .rgb,
              rgb.bitsPerComponent == 8,
              rgb.bitsPerPixel == 32,
              rgb.dataProvider?.data != nil else { return nil }
        return UIImage(cgImage: rgb, scale: 1, orientation: .up)
    }
}

enum OpenLensCanvas {
    // A full-screen 1-bit image consists of many BLE packets. Keep frames from
    // overlapping: the newest pending frame replaces an obsolete one.
    private static let minimumFrameSpacing: TimeInterval = 8.0
    private static var lastFrameAt: Date = .distantPast
    private static var pendingFrame: (glasses: Glasses, image: UIImage)?
    private static var lastError: String?
    private static var flushScheduled = false

    static func cancelPending() {
        if Thread.isMainThread { pendingFrame = nil }
        else { DispatchQueue.main.async { pendingFrame = nil } }
    }

    private static func send(_ glasses: Glasses, image: UIImage) {
        guard let rgb = OpenLensRGBImage.normalize(image) else {
            lastError = "Unable to produce an 8-bit RGB image; not sent."
            print("OpenLens:", lastError ?? "Invalid image")
            return
        }
        lastError = nil
        lastFrameAt = Date()
        glasses.clear()
        glasses.imgStream1bpp(image: rgb,
                              x: Int16(OpenLensDisplayGeometry.textImageX),
                              y: Int16(OpenLensDisplayGeometry.textImageY))
    }

    private static func enqueue(_ glasses: Glasses, image: UIImage) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { enqueue(glasses, image: image) }
            return
        }
        let remaining = minimumFrameSpacing - Date().timeIntervalSince(lastFrameAt)
        if remaining <= 0 && !flushScheduled {
            pendingFrame = nil
            send(glasses, image: image)
            return
        }
        pendingFrame = (glasses, image)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, remaining)) {
            flushScheduled = false
            guard let frame = pendingFrame else { return }
            pendingFrame = nil
            send(frame.glasses, image: frame.image)
        }
    }

    /// Only user's message is displayed. No OPENLENS header or divider can
    /// consume space, overlap another line, or appear as stray fragments.
    /// Accurate 304×240 rendering, full 1-bit framebuffer, centered at (0,8).
    static func render(lines: [String], size: OpenLensTextSize = .selected) -> UIImage {
        let width = OpenLensDisplayGeometry.textImageWidth
        let height = OpenLensDisplayGeometry.textImageHeight
        let inset = CGFloat(OpenLensDisplayGeometry.textInset)
        let available = CGFloat(width) - 2 * inset
        let printable = Array(lines.prefix(size.linesPerPage)).map {
            String(OpenLensText.sanitize($0).prefix(size.charactersPerLine))
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let fontSize = CGFloat(size.fontHeight)
        var font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let referenceWidth = printable.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        // Pixel-measured guard: never truncate glyphs at the right edge.
        if referenceWidth > available && referenceWidth > 0 {
            font = UIFont.monospacedSystemFont(
                ofSize: fontSize * available / referenceWidth * 0.97,
                weight: .semibold
            )
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                               format: format)
        let approximateBlockHeight =
            CGFloat(max(0, printable.count - 1) * size.lineSpacing) + font.lineHeight
        let originY = max(8, (CGFloat(height) - approximateBlockHeight) / 2)
        let image = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            for (i, line) in printable.enumerated() {
                let text = line as NSString
                let measured = text.size(withAttributes: attrs)
                let x = (printable.count == 1 ? (CGFloat(width) - measured.width) / 2 : inset)
                        + CGFloat(OpenLensBitmapSettings.offsetX)
                let y = originY + CGFloat(i * size.lineSpacing)
                        + CGFloat(OpenLensBitmapSettings.offsetY)
                text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }
        guard OpenLensBitmapSettings.rotated else { return image }
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: CGFloat(width), y: CGFloat(height))
            ctx.cgContext.rotate(by: .pi)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Stream any 1-bit HUD frame through the same guarded RGB conversion
    /// and BLE pacing as text. Used for MapKit route previews.
    @discardableResult
    static func showImage(_ glasses: Glasses, image: UIImage) -> UIImage {
        enqueue(glasses, image: image)
        return image
    }

    @discardableResult
    static func show(_ glasses: Glasses, title: String, lines: [String],
                     size: OpenLensTextSize = .selected) -> UIImage {
        let image = render(lines: lines, size: size)
        // The same proven API as Photos, not the SDK native text renderer.
        // A cooldown prevents fragments from successive frames interleaving.
        enqueue(glasses, image: image)
        return image
    }

    @discardableResult
    static func show(_ glasses: Glasses, title: String, message: String,
                     size: OpenLensTextSize = .selected) -> UIImage {
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
/// A walking-route companion with two distinct optical modes:
/// instructions (all pages, including street names) or high-contrast mini-map.
final class OpenLensRoutePreviewViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    private let glasses: Glasses
    private let locationManager = CLLocationManager()
    private let destination = UITextField()
    private let status = UILabel()
    private let instruction = UILabel()
    private let position = UILabel()
    private let pageLabel = UILabel()
    private let modeSelector = UISegmentedControl(items: ["Directions text", "Street map"])
    private let mapScope = UISegmentedControl(items: ["Next turn", "Whole route"])
    private let previousTurn = UIButton(type: .system)
    private let nextTurn = UIButton(type: .system)
    private let previousPage = UIButton(type: .system)
    private let nextPage = UIButton(type: .system)
    private let glassesPreview = UIImageView()
    private let mapView = MKMapView()
    private let followSwitch = UISwitch()
    private let mapRenderer = OpenLensMapRenderer()
    private var pendingDestination: String?
    private var route: MKRoute?
    private var targetItem: MKMapItem?
    private var steps: [MKRoute.Step] = []
    private var stepIndex = 0
    private var textPages: [[String]] = []
    private var textPageIndex = 0
    private var lastMapRefresh = Date.distantPast
    private var lastLocation: CLLocation?
    private var lookup: MKLocalSearch?
    private var directions: MKDirections?
    private var active = false

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Walking directions"
        let content = LensUI.stack(in: view)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 15

        content.addArrangedSubview(LensUI.section("Walk with OpenLens",
            detail: "Choose full written directions or a real MapKit street map on your glasses. Maps are previews, not automatic AR navigation."))
        destination.placeholder = "Destination name or street address"
        destination.textColor = .white
        destination.font = .systemFont(ofSize: 16)
        destination.backgroundColor = LensUI.card
        destination.layer.cornerRadius = 13
        destination.autocapitalizationType = .words
        destination.returnKeyType = .search
        destination.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        destination.leftViewMode = .always
        destination.heightAnchor.constraint(equalToConstant: 52).isActive = true
        content.addArrangedSubview(destination)
        content.addArrangedSubview(LensUI.button("Find a walking route", icon: "figure.walk") { [weak self] in self?.findRoute() })

        content.addArrangedSubview(LensUI.section("Show on glasses"))
        modeSelector.selectedSegmentIndex = 0
        modeSelector.selectedSegmentTintColor = LensUI.accent
        modeSelector.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        content.addArrangedSubview(modeSelector)
        mapScope.selectedSegmentIndex = 0
        mapScope.selectedSegmentTintColor = LensUI.accent
        mapScope.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        content.addArrangedSubview(mapScope)
        mapScope.isHidden = true

        position.textColor = LensUI.accent
        position.font = .systemFont(ofSize: 15, weight: .bold)
        position.text = "Find a destination to begin"
        content.addArrangedSubview(position)

        instruction.textColor = .white
        instruction.font = .preferredFont(forTextStyle: .body)
        instruction.numberOfLines = 0
        instruction.text = "The full next instruction—including the street name—will appear here."
        instruction.heightAnchor.constraint(greaterThanOrEqualToConstant: 75).isActive = true
        content.addArrangedSubview(LensUI.card(instruction))

        glassesPreview.backgroundColor = .black
        glassesPreview.contentMode = .scaleAspectFit
        glassesPreview.layer.cornerRadius = 15
        glassesPreview.clipsToBounds = true
        glassesPreview.heightAnchor.constraint(equalToConstant: 220).isActive = true
        glassesPreview.accessibilityLabel = "Exact screen image queued for ENGO 3"
        content.addArrangedSubview(glassesPreview)

        pageLabel.textColor = LensUI.accent
        pageLabel.textAlignment = .center
        pageLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        content.addArrangedSubview(pageLabel)
        previousPage.configuration = .bordered()
        previousPage.configuration?.title = "◀ Previous page"
        nextPage.configuration = .bordered()
        nextPage.configuration?.title = "Next page ▶"
        previousPage.addTarget(self, action: #selector(backPage), for: .touchUpInside)
        nextPage.addTarget(self, action: #selector(forwardPage), for: .touchUpInside)
        content.addArrangedSubview(buttonRow(previousPage, nextPage))
        previousTurn.configuration = .filled()
        previousTurn.configuration?.title = "◀ Previous turn"
        nextTurn.configuration = .filled()
        nextTurn.configuration?.title = "Next turn ▶"
        previousTurn.addTarget(self, action: #selector(backTurn), for: .touchUpInside)
        nextTurn.addTarget(self, action: #selector(forwardTurn), for: .touchUpInside)
        content.addArrangedSubview(buttonRow(previousTurn, nextTurn))

        content.addArrangedSubview(LensUI.section("Phone map", detail: "Interactive color map on your phone; black-and-white preview above matches the glasses."))
        mapView.delegate = self
        mapView.isRotateEnabled = true
        mapView.showsCompass = true
        mapView.showsUserLocation = true
        mapView.layer.cornerRadius = 16
        mapView.heightAnchor.constraint(equalToConstant: 235).isActive = true
        content.addArrangedSubview(mapView)
        followSwitch.onTintColor = LensUI.accent
        followSwitch.addTarget(self, action: #selector(changeFollow), for: .valueChanged)
        let followRow = UIStackView(arrangedSubviews: [
            LensUI.label("Follow my location on the map", size: 14), followSwitch
        ])
        followRow.distribution = .equalSpacing
        followRow.alignment = .center
        content.addArrangedSubview(LensUI.card(followRow))
        content.addArrangedSubview(LensUI.button("Open in Apple Maps for live navigation",
                                                icon: "map.fill") { [weak self] in self?.openAppleMaps() })
        content.addArrangedSubview(LensUI.button("Resend current map / instruction",
                                                icon: "arrow.clockwise") { [weak self] in self?.displayCurrent() })
        status.textColor = LensUI.muted
        status.font = .systemFont(ofSize: 13)
        status.numberOfLines = 0
        status.text = "Choose a destination. Location is used only for the route and optional moving map dot."
        content.addArrangedSubview(status)
        content.addArrangedSubview(LensUI.label(
            "For safety, use phone controls only when stopped. Map frames update periodically, not continuously; verify turns and crossings in the real world.",
            size: 12, color: LensUI.muted))
        updateControls()
    }

    private func buttonRow(_ left: UIView, _ right: UIView) -> UIStackView {
        let row = UIStackView(arrangedSubviews: [left, right])
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        active = true
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        active = false
        lookup?.cancel()
        directions?.cancel()
        mapRenderer.cancel()
        locationManager.stopUpdatingLocation()
        OpenLensCanvas.cancelPending()
    }
    private func updateControls() {
        previousTurn.isEnabled = stepIndex > 0
        nextTurn.isEnabled = stepIndex + 1 < steps.count
        let textMode = modeSelector.selectedSegmentIndex == 0
        previousPage.isEnabled = textMode && textPageIndex > 0
        nextPage.isEnabled = textMode && textPageIndex + 1 < textPages.count
        mapScope.isHidden = textMode
        pageLabel.text = textMode && !textPages.isEmpty
            ? "INSTRUCTION PAGE \(textPageIndex + 1) / \(textPages.count)"
            : "MAP PREVIEW"
    }
    private func findRoute() {
        destination.resignFirstResponder()
        guard let query = destination.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            status.text = "Please enter a destination."
            return
        }
        pendingDestination = query
        route = nil
        steps = []
        targetItem = nil
        textPages = []
        stepIndex = 0
        textPageIndex = 0
        mapRenderer.cancel()
        updateControls()
        guard CLLocationManager.locationServicesEnabled() else {
            status.text = "Location Services are off. Enable them in iPhone Settings."
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            status.text = "Allow location access to plan a walking route."
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            status.text = "Finding your current location…"
            locationManager.requestLocation()
        default:
            status.text = "Allow location for OpenLens in iPhone Settings."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        if (authorization == .authorizedAlways || authorization == .authorizedWhenInUse),
           pendingDestination != nil {
            manager.requestLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let here = locations.last else { return }
        lastLocation = here
        if let query = pendingDestination {
            pendingDestination = nil
            findDestination(query, from: here)
        } else if followSwitch.isOn && !steps.isEmpty && modeSelector.selectedSegmentIndex == 1 &&
                  Date().timeIntervalSince(lastMapRefresh) > 20 {
            lastMapRefresh = Date()
            renderMiniMap()
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status.text = "Location unavailable: \(error.localizedDescription)"
    }
    private func findDestination(_ query: String, from here: CLLocation) {
        lookup?.cancel()
        directions?.cancel()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 30000, longitudinalMeters: 30000)
        status.text = "Searching for your destination…"
        let search = MKLocalSearch(request: request)
        lookup = search
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self, self.active else { return }
                guard let target = response?.mapItems.first else {
                    self.status.text = error?.localizedDescription ?? "Destination not found."
                    return
                }
                self.targetItem = target
                let plan = MKDirections.Request()
                plan.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
                plan.destination = target
                plan.transportType = .walking
                self.status.text = "Calculating walking directions…"
                let request = MKDirections(request: plan)
                self.directions = request
                request.calculate { [weak self] response, error in
                    DispatchQueue.main.async {
                        guard let self = self, self.active else { return }
                        guard let result = response?.routes.first else {
                            self.status.text = error?.localizedDescription ?? "No walking route could be calculated."
                            return
                        }
                        self.route = result
                        self.steps = result.steps.filter {
                            !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        self.stepIndex = 0
                        guard !self.steps.isEmpty else {
                            self.status.text = "MapKit returned no instructions for this route."
                            return
                        }
                        self.mapView.removeOverlays(self.mapView.overlays)
                        self.mapView.addOverlay(result.polyline)
                        self.mapView.setVisibleMapRect(result.polyline.boundingMapRect,
                            edgePadding: UIEdgeInsets(top: 38, left: 30, bottom: 38, right: 30),
                            animated: false)
                        self.showStep()
                    }
                }
            }
        }
    }
    private func showStep() {
        guard steps.indices.contains(stepIndex) else { return }
        let step = steps[stepIndex]
        let distance = Int(step.distance.rounded())
        position.text = "TURN \(stepIndex + 1) OF \(steps.count) • ~\(distance) m"
        instruction.text = step.instructions
        // Keep the ENTIRE instruction as page state, rather than showing only
        // page one and dropping the street name at the end.
        textPages = OpenLensText.pages(step.instructions, size: .selected)
        textPageIndex = 0
        if step.polyline.pointCount > 0 {
            let bounds = step.polyline.boundingMapRect
            if bounds.size.width > 0 && bounds.size.height > 0 {
                mapView.setVisibleMapRect(bounds,
                    edgePadding: UIEdgeInsets(top: 70, left: 56, bottom: 70, right: 56),
                    animated: true)
            }
        }
        displayCurrent()
    }
    @objc private func modeChanged() {
        mapRenderer.cancel()
        displayCurrent()
    }
    @objc private func backTurn() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        showStep()
    }
    @objc private func forwardTurn() {
        guard stepIndex + 1 < steps.count else { return }
        stepIndex += 1
        showStep()
    }
    @objc private func backPage() {
        guard textPageIndex > 0 else { return }
        textPageIndex -= 1
        displayInstructionPage()
    }
    @objc private func forwardPage() {
        guard textPageIndex + 1 < textPages.count else { return }
        textPageIndex += 1
        displayInstructionPage()
    }
    private func displayCurrent() {
        updateControls()
        guard !steps.isEmpty else {
            status.text = "Search for a route first."
            return
        }
        if modeSelector.selectedSegmentIndex == 0 {
            mapRenderer.cancel()
            displayInstructionPage()
        } else {
            renderMiniMap()
        }
    }
    private func displayInstructionPage() {
        guard textPages.indices.contains(textPageIndex) else { return }
        let lines = textPages[textPageIndex]
        glassesPreview.image = OpenLensCanvas.show(glasses,
            title: "WALK TURN \(stepIndex + 1)", lines: lines)
        updateControls()
        status.text = "Showing instruction page \(textPageIndex + 1) of \(textPages.count) for turn \(stepIndex + 1). All street names remain available. Allow ~8 seconds between frames."
    }
    private func renderMiniMap() {
        guard let route = route, steps.indices.contains(stepIndex) else { return }
        updateControls()
        status.text = "Preparing \(mapScope.selectedSegmentIndex == 1 ? "whole-route" : "next-turn") map for ENGO 3…"
        mapRenderer.snapshot(route: route, step: steps[stepIndex],
                             overview: mapScope.selectedSegmentIndex == 1,
                             currentLocation: lastLocation?.coordinate) { [weak self] image, error in
            DispatchQueue.main.async {
                guard let self = self, self.active && self.modeSelector.selectedSegmentIndex == 1 else { return }
                guard let image = image else {
                    self.status.text = error ?? "Could not render the map."
                    return
                }
                self.glassesPreview.image = OpenLensCanvas.showImage(self.glasses, image: image)
                self.lastMapRefresh = Date()
                self.status.text = "Street map queued for ENGO 3. The thick bright line is this turn; the circle shows location if available. Static preview, not live guidance."
            }
        }
    }
    @objc private func changeFollow() {
        if followSwitch.isOn {
            guard locationManager.authorizationStatus == .authorizedWhenInUse ||
                  locationManager.authorizationStatus == .authorizedAlways else {
                followSwitch.isOn = false
                status.text = "Grant location permission to follow your position."
                return
            }
            locationManager.startUpdatingLocation()
            mapView.setUserTrackingMode(.follow, animated: true)
            status.text = "Following phone location. A refreshed map can be sent about every 20 seconds while this screen is open."
        } else {
            locationManager.stopUpdatingLocation()
            mapView.setUserTrackingMode(.none, animated: true)
        }
    }
    private func openAppleMaps() {
        guard let target = targetItem else {
            status.text = "Find a destination first."
            return
        }
        target.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let line = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor.systemGreen
            renderer.lineWidth = 5
            renderer.lineJoin = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
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
