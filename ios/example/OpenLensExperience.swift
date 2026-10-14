// OpenLens iOS experience on top of the existing ActiveLook SDK and demo app.
// Keep vendor diagnostic commands available in Advanced Tools.
import UIKit
import PhotosUI
import ActiveLookSDK

enum LensUI {
    static let bg = UIColor(red: 0.045, green: 0.066, blue: 0.075, alpha: 1)
    static let card = UIColor(red: 0.095, green: 0.13, blue: 0.14, alpha: 1)
    static let accent = UIColor(red: 0.54, green: 0.97, blue: 0.71, alpha: 1)
    static let muted = UIColor(red: 0.66, green: 0.74, blue: 0.73, alpha: 1)

    static func label(_ title: String, size: CGFloat = 16, weight: UIFont.Weight = .regular, color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = color
        label.font = .systemFont(ofSize: size, weight: weight)
        label.numberOfLines = 0
        return label
    }

    static func button(_ title: String, icon: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 12
        config.baseBackgroundColor = card
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 17, bottom: 18, trailing: 17)
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func tile(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = title
        config.subtitle = subtitle
        config.image = UIImage(systemName: symbol)
        config.imagePlacement = .top
        config.imagePadding = 11
        config.titleAlignment = .center
        config.baseBackgroundColor = card
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 10, bottom: 18, trailing: 10)
        button.configuration = config
        button.titleLabel?.numberOfLines = 2
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func pair(_ first: UIView, _ second: UIView) -> UIStackView {
        let row = UIStackView(arrangedSubviews: [first, second])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    static func section(_ title: String, detail: String? = nil) -> UIStackView {
        let group = UIStackView()
        group.axis = .vertical
        group.spacing = 5
        group.addArrangedSubview(label(title, size: 21, weight: .bold))
        if let detail = detail { group.addArrangedSubview(label(detail, size: 13, color: muted)) }
        return group
    }

    static func stack(in view: UIView) -> UIStackView {
        view.backgroundColor = bg
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 22),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        return content
    }

    static func card(_ inner: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = card
        container.layer.cornerRadius = 18
        inner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18)
        ])
        return container
    }
}

enum OpenLensOrientation {
    private static let preference = "openlens.display.rotated180"
    // The original demo used bottomRL and was physically inverted on ENGO 3.
    static var isRotated: Bool {
        get { UserDefaults.standard.bool(forKey: preference) }
        set { UserDefaults.standard.set(newValue, forKey: preference) }
    }
    static var rotation: TextRotation { isRotated ? .bottomRL : .topLR }
}

final class OpenLensHomeViewController: UIViewController {
    private let glasses: Glasses
    private let battery = LensUI.label("Reading battery…", size: 14, color: LensUI.muted)

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "OpenLens"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Disconnect", style: .plain, target: self, action: #selector(disconnect))
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.label("OPENLENS  /  CONNECTED", size: 12, weight: .bold, color: LensUI.accent))
        content.addArrangedSubview(LensUI.label("Your world, in view.", size: 30, weight: .bold))
        let device = UIStackView(arrangedSubviews: [
            LensUI.label("◉  ENGO 3 is connected", size: 17, weight: .bold, color: LensUI.accent),
            LensUI.label(glasses.name, size: 14, color: LensUI.muted),
            battery
        ])
        device.axis = .vertical
        device.spacing = 8
        content.addArrangedSubview(LensUI.card(device))
        content.addArrangedSubview(LensUI.section("Display", detail: "Put the important things right in front of you."))
        content.addArrangedSubview(LensUI.pair(
            LensUI.tile("Text", subtitle: "Send a message", symbol: "text.bubble.fill") { [weak self] in self?.hud(0) },
            LensUI.tile("Photos", subtitle: "High-contrast HUD", symbol: "photo.fill") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensImageViewController(self.glasses))
            }
        ))
        content.addArrangedSubview(LensUI.section("AI & speech", detail: "Phone microphone and a private AI relay."))
        content.addArrangedSubview(LensUI.pair(
            LensUI.tile("Captions", subtitle: "Live speech text", symbol: "waveform") { [weak self] in self?.hud(1) },
            LensUI.tile("Ask AI", subtitle: "Relay required", symbol: "sparkles") { [weak self] in self?.hud(2) }
        ))
        content.addArrangedSubview(LensUI.section("Everyday tools", detail: "Useful even without an AI subscription."))
        content.addArrangedSubview(LensUI.pair(
            LensUI.tile("Quick cards", subtitle: "Saved reminders", symbol: "rectangle.stack.fill") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensCardsViewController(self.glasses))
            },
            LensUI.tile("Presenter", subtitle: "Page through notes", symbol: "rectangle.on.rectangle") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensPresenterViewController(self.glasses))
            }
        ))
        content.addArrangedSubview(LensUI.pair(
            LensUI.tile("Focus", subtitle: "Timer and clock", symbol: "timer") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensFocusViewController(self.glasses))
            },
            LensUI.tile("Walking", subtitle: "Route preview", symbol: "figure.walk") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensRoutePreviewViewController(self.glasses))
            }
        ))
        content.addArrangedSubview(LensUI.section("Device control"))
        content.addArrangedSubview(LensUI.pair(
            LensUI.tile("Settings", subtitle: "Brightness, rotate", symbol: "slider.horizontal.3") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensDeviceSettingsViewController(self.glasses))
            },
            LensUI.tile("Diagnostics", subtitle: "Firmware, battery", symbol: "stethoscope") { [weak self] in
                guard let self = self else { return }; self.open(OpenLensDiagnosticsViewController(self.glasses))
            }
        ))
        content.addArrangedSubview(LensUI.button("Clear glasses display", icon: "xmark.circle") { [weak self] in
            self?.glasses.clear()
        })
        content.addArrangedSubview(LensUI.button("Advanced developer tools", icon: "wrench.and.screwdriver") { [weak self] in
            guard let self = self else { return }; self.open(CommandsMenuTableViewController(self.glasses))
        })
        content.addArrangedSubview(LensUI.label("Some controls require ENGO 3 firmware support. Open Diagnostics to see device-reported values. AI needs a separate authenticated relay.", size: 12, color: LensUI.muted))
        updateBattery()
    }

    private func open(_ screen: UIViewController) {
        screen.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(screen, animated: true)
    }
    private func hud(_ mode: Int) { open(OpenLensHUDViewController(glasses, initialMode: mode)) }
    private func updateBattery() {
        glasses.battery { [weak self] percent in
            DispatchQueue.main.async { self?.battery.text = "Battery  \(percent)%" }
        }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); updateBattery() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.viewControllers.contains(self) == false { glasses.disconnect() }
    }
    @objc private func disconnect() {
        glasses.disconnect()
        navigationController?.popToRootViewController(animated: true)
    }
}

final class OpenLensDeviceSettingsViewController: UIViewController {
    private let glasses: Glasses
    private let orientation = UISegmentedControl(items: ["Normal", "Rotated 180°"])
    private let brightness = UISlider()
    private let autoBrightness = UISwitch()
    private let gestures = UISwitch()
    private let status = LensUI.label("Reading device settings…", size: 13, color: LensUI.muted)
    private var reading = false

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glasses settings"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("Display orientation", detail: "Switch if text appears upside down, then tap Test."))
        orientation.selectedSegmentIndex = OpenLensOrientation.isRotated ? 1 : 0
        orientation.selectedSegmentTintColor = LensUI.accent
        orientation.addTarget(self, action: #selector(orientationChanged), for: .valueChanged)
        content.addArrangedSubview(orientation)
        content.addArrangedSubview(LensUI.button("Show orientation test", icon: "textformat") { [weak self] in self?.testOrientation() })
        content.addArrangedSubview(LensUI.section("Display brightness", detail: "Disable automatic brightness to use the manual setting."))
        brightness.minimumValue = 0
        brightness.maximumValue = 15
        brightness.value = 7
        brightness.minimumTrackTintColor = LensUI.accent
        brightness.addTarget(self, action: #selector(changeLuminance), for: .touchUpInside)
        brightness.addTarget(self, action: #selector(changeLuminance), for: .touchUpOutside)
        content.addArrangedSubview(brightness)
        content.addArrangedSubview(toggle("Automatic brightness", autoBrightness, #selector(changeAutoBrightness)))
        content.addArrangedSubview(toggle("Gesture detection", gestures, #selector(changeGestures)))
        content.addArrangedSubview(LensUI.button("Refresh actual settings", icon: "arrow.clockwise") { [weak self] in self?.refresh() })
        content.addArrangedSubview(status)
        content.addArrangedSubview(LensUI.label("Commands are not guaranteed to be accepted by all firmware versions. Refresh reads back the actual settings from the device.", size: 12, color: LensUI.muted))
        refresh()
    }

    private func toggle(_ title: String, _ control: UISwitch, _ action: Selector) -> UIView {
        control.onTintColor = LensUI.accent
        control.addTarget(self, action: action, for: .valueChanged)
        let name = LensUI.label(title, size: 15, weight: .medium)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [name, control])
        row.alignment = .center
        row.distribution = .equalSpacing
        return LensUI.card(row)
    }

    @objc private func orientationChanged() {
        OpenLensOrientation.isRotated = orientation.selectedSegmentIndex == 1
        status.text = "Orientation preference saved. Tap Show orientation test."
    }
    private func testOrientation() {
        glasses.clear()
        glasses.txt(x: 26, y: 112, rotation: OpenLensOrientation.rotation, font: 2, color: 15, string: "OPENLENS - THIS WAY UP")
        status.text = "Test queued. If inverted, choose the other orientation."
    }
    @objc private func changeLuminance() {
        let level = UInt8(brightness.value.rounded())
        glasses.luma(level: level)
        status.text = "Brightness \(level)/15 requested. Refresh to verify."
    }
    @objc private func changeAutoBrightness() {
        glasses.als(enabled: autoBrightness.isOn)
        status.text = "Auto brightness \(autoBrightness.isOn ? "on" : "off") requested. Refresh to verify."
    }
    @objc private func changeGestures() {
        glasses.gesture(enabled: gestures.isOn)
        status.text = "Gestures \(gestures.isOn ? "on" : "off") requested. Refresh to verify."
    }
    private func refresh() {
        guard !reading else { return }
        reading = true
        status.text = "Reading settings from ENGO 3…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, self.reading else { return }
            self.reading = false
            self.status.text = "Settings read timed out. Try Refresh again; this firmware may not reply."
        }
        glasses.settings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.reading = false
                self.brightness.value = Float(settings.luma)
                self.autoBrightness.isOn = settings.brightnessAdjustmentEnabled
                self.gestures.isOn = settings.gestureDetectionEnabled
                self.status.text = "Reported: brightness \(settings.luma)/15, auto \(settings.brightnessAdjustmentEnabled ? "on" : "off"), gestures \(settings.gestureDetectionEnabled ? "on" : "off")."
            }
        }
    }
}

final class OpenLensImageViewController: UIViewController, PHPickerViewControllerDelegate {
    private let glasses: Glasses
    private let preview = UIImageView()
    private let status = LensUI.label("Choose a photo to begin.", size: 14, color: LensUI.muted)
    private let quality = UISegmentedControl(items: ["High contrast", "Dither", "More detail"])
    private let rotate = UISwitch()
    private let invertColors = UISwitch()
    private let fillFrame = UISwitch()
    private var selected: UIImage?
    private var transmitting = false

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Display a photo"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("A photo in your view", detail: "ENGO 3 is a compact monochrome HUD. Simple icons and high-contrast images work best."))
        preview.contentMode = .scaleAspectFit
        preview.backgroundColor = .black
        preview.layer.cornerRadius = 16
        preview.clipsToBounds = true
        preview.heightAnchor.constraint(equalToConstant: 200).isActive = true
        content.addArrangedSubview(preview)
        content.addArrangedSubview(LensUI.button("Choose photo", icon: "photo") { [weak self] in self?.choose() })
        quality.selectedSegmentIndex = 0
        quality.selectedSegmentTintColor = LensUI.accent
        content.addArrangedSubview(quality)
        let row = UIStackView(arrangedSubviews: [LensUI.label("Rotate image 180°", size: 15), rotate])
        row.distribution = .equalSpacing
        row.alignment = .center
        rotate.onTintColor = LensUI.accent
        content.addArrangedSubview(LensUI.card(row))
        let invertRow = UIStackView(arrangedSubviews: [LensUI.label("Invert black / white", size: 15), invertColors])
        invertRow.distribution = .equalSpacing
        invertRow.alignment = .center
        invertColors.onTintColor = LensUI.accent
        content.addArrangedSubview(LensUI.card(invertRow))
        let cropRow = UIStackView(arrangedSubviews: [LensUI.label("Fill frame (crop edges)", size: 15), fillFrame])
        cropRow.distribution = .equalSpacing
        cropRow.alignment = .center
        fillFrame.onTintColor = LensUI.accent
        content.addArrangedSubview(LensUI.card(cropRow))
        content.addArrangedSubview(LensUI.button("Show on glasses", icon: "eyeglasses") { [weak self] in self?.sendImage() })
        content.addArrangedSubview(LensUI.button("Clear display", icon: "xmark.circle") { [weak self] in
            self?.glasses.clear()
            self?.status.text = "Clear command sent."
        })
        content.addArrangedSubview(status)
        content.addArrangedSubview(LensUI.label("Image data is queued over BLE. This preview cannot yet verify every packet arrived. Try a simple black-and-white logo first.", size: 12, color: LensUI.muted))
    }

    private func choose() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            status.text = "No image selected."
            return
        }
        status.text = "Loading photo…"
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let image = object as? UIImage else {
                    self.status.text = error?.localizedDescription ?? "Could not open this photo."
                    return
                }
                self.selected = image
                self.preview.image = image
                self.status.text = "Photo ready. Tap Show on glasses."
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
            glasses.subscribeToFlowControlNotifications { [weak self] state in
                switch state {
                case .error, .overflow, .unexpectedDataType, .missingConfiguration:
                    DispatchQueue.main.async { self?.status.text = "Glasses reported transfer issue: \(state). Try High contrast or a smaller image." }
                default: break
                }
            }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        glasses.unsubscribeFromFlowControlNotifications()
    }

    private func sendImage() {
        guard !transmitting else { status.text = "Wait for the previous image transfer."; return }
        guard let image = selected else { status.text = "Choose a photo first."; return }
        transmitting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.transmitting = false }
        status.text = "Converting to monochrome…"
        let mode = quality.selectedSegmentIndex
        let flip = rotate.isOn
        let invert = invertColors.isOn
        let crop = fillFrame.isOn
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let processed = Self.prepare(image, mode: mode, rotate: flip, invert: invert, crop: crop)
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let processed = processed else { self.status.text = "Image conversion failed."; return }
                self.preview.image = processed
                self.glasses.clear()
                // Do not call the SDK's generic imgStream 1bpp wrapper: v4.5.5
                // incorrectly passes x for y. Call the direct method instead.
                if mode == 2 {
                    self.glasses.imgStream4bppHeatShrink(image: processed, x: 56, y: 80)
                } else {
                    self.glasses.imgStream1bpp(image: processed, x: 56, y: 80)
                }
                // Streaming does not require cfgWrite/cfgSet or an immediate imgDelete.
                let format = mode == 2 ? "4-bit compressed" : mode == 1 ? "1-bit dithered" : "1-bit high contrast"
                self.status.text = "Queued 192×96 \(format) image. Check ENGO 3; retry with High contrast if missing."
            }
        }
    }

    /// Preprocess for the SDK's monochrome encoder: resize, threshold or dither,
    /// invert if desired, and optionally turn the final frame 180 degrees.
    private static func prepare(_ image: UIImage, mode: Int, rotate: Bool, invert: Bool, crop: Bool) -> UIImage? {
        let width = 192, height = 96
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let normalized = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            let scaleX = CGFloat(width) / image.size.width
            let scaleY = CGFloat(height) / image.size.height
            let scale = crop ? max(scaleX, scaleY) : min(scaleX, scaleY)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (CGFloat(width) - size.width) / 2,
                                  y: (CGFloat(height) - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        guard let input = normalized.cgImage else { return nil }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let inputContext = CGContext(data: &bytes, width: width, height: height,
                                           bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        inputContext.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))
        let grays = stride(from: 0, to: bytes.count, by: 4).map { i -> Double in
            let light = 0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])
            return invert ? 255 - light : light
        }
        let dithered = mode == 1 ? OpenLensText.dither(grays, width: width) : []
        for pixel in 0..<(width * height) {
            let brightness: UInt8
            if mode == 1 { brightness = dithered[pixel] }
            else if mode == 2 { brightness = UInt8(grays[pixel].rounded()) }
            else { brightness = grays[pixel] >= 125 ? 255 : 0 }
            let i = pixel * 4
            bytes[i] = brightness
            bytes[i + 1] = brightness
            bytes[i + 2] = brightness
            bytes[i + 3] = 255
        }
        guard let outputContext = CGContext(data: &bytes, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let output = outputContext.makeImage() else { return nil }
        let result = UIImage(cgImage: output)
        guard rotate else { return result }
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: CGFloat(width), y: CGFloat(height))
            ctx.cgContext.rotate(by: .pi)
            result.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
