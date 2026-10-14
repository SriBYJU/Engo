/*
 
Copyright 2021 Microoled
Licensed under the Apache License, Version 2.0 (the “License”);
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an “AS IS” BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 
*/

import UIKit
import ActiveLookSDK

class CommandsMenuTableViewController: CommandsTableViewController {

    // MARK: - Life cycle
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Commands"

        commandNames = [
            "OpenLens HUD",
            "General",
            "Display luminance",
            "Optical sensor",
            "Graphics",
            "Image",
            "Animation",
            "Font",
            "Layout",
            "Page",
            "Gauge",
            "Statistics",
            "Configuration",
            "Notifications",
            "Demo viewer"
        ]

        commandActions = [
            self.showOpenLens,
            self.showGeneralCommands,
            self.showDisplayCommands,
            self.showOpticalCommands,
            self.showGraphicsCommands,
            self.showImageCommands,
            self.showAnimationCommands,
            self.showFontCommands,
            self.showLayoutCommands,
            self.showPageCommands,
            self.showGaugeCommands,
            self.showStatisticsCommands,
            self.showConfigurationCommands,
            self.showNotificationsViewController,
            self.showViewerCommands
        ]
        
        glasses.subscribeToFlowControlNotifications { (flowControlState) -> (Void) in
            print("flow control state update: \(flowControlState)")
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        
        // Disconnect glasses when navigating back to list
        if navigationController?.viewControllers.firstIndex(of: self) == nil {
            glasses.disconnect()
        }
        
        super.viewDidDisappear(animated)
    }
    
    
    // MARK: - Navigation
    
    func showOpenLens() {
        navigationController?.pushViewController(OpenLensHUDViewController(glasses), animated: true)
    }

    func showGeneralCommands() {
        navigationController?.pushViewController(GeneralCommandsViewController(glasses), animated: true)
    }
    
    func showDisplayCommands() {
        navigationController?.pushViewController(DisplayCommandsViewController(glasses), animated: true)
    }
    
    func showOpticalCommands() {
        navigationController?.pushViewController(OpticalCommandsViewController(glasses), animated: true)
    }
    
    func showGraphicsCommands() {
        navigationController?.pushViewController(GraphicsCommandsViewController(glasses), animated: true)
    }
    
    func showImageCommands() {
        navigationController?.pushViewController(ImageCommandsViewController(glasses), animated: true)
    }
    
    func showAnimationCommands(){
        navigationController?.pushViewController(AnimationCommandsViewController(glasses), animated: true)
    }
    
    func showFontCommands() {
        navigationController?.pushViewController(FontCommandsViewController(glasses), animated: true)
    }
    
    func showLayoutCommands() {
        navigationController?.pushViewController(LayoutCommandsViewController(glasses), animated: true)
    }
    
    func showPageCommands() {
        navigationController?.pushViewController(PageCommandsViewController(glasses), animated: true)
    }
    
    func showGaugeCommands() {
        navigationController?.pushViewController(GaugeCommandsViewController(glasses), animated: true)
    }
    
    func showStatisticsCommands() {
        navigationController?.pushViewController(StatisticsCommandsViewController(glasses), animated: true)
    }
    
    func showConfigurationCommands() {
        navigationController?.pushViewController(ConfigurationCommandsViewController(glasses), animated: true)
    }

    func showNotificationsViewController() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let viewController = storyboard.instantiateViewController(identifier: "NotificationsViewController") as? NotificationsViewController {
            viewController.glasses = glasses
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
    
    func showViewerCommands() {
        navigationController?.pushViewController(ViewerCommandsViewController(glasses), animated: true)
    }
}


// MARK: - OpenLens Alpha (new code; the vendor demo remains intact)
//
// An iPhone companion HUD built on the vendor's real Glasses SDK instance.
// The ENGO 3 display's dimensions, fonts, orientation and color require
// confirmation using physical hardware before production use.
import Speech
import AVFoundation
import MapKit
import CoreLocation

final class OpenLensHUDViewController: UIViewController, CLLocationManagerDelegate {
    private let glasses: Glasses
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var listening = false
    private var transcript = ""
    private var lastUpdate = Date.distantPast
    private let modes = ["HUD", "CAPTIONS", "AI", "MAPS"]
    private let segment = UISegmentedControl(items: ["HUD", "Captions", "AI", "Maps"])
    private let field = UITextField()
    private let preview = UILabel()
    private let status = UILabel()
    private let mic = UIButton(type: .system)
    private let send = UIButton(type: .system)

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "OpenLens"
        view.backgroundColor = UIColor(red: 0.045, green: 0.072, blue: 0.06, alpha: 1)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Settings", style: .plain, target: self, action: #selector(settings))
        locationManager.delegate = self
        let accent = UIColor(red: 0.44, green: 0.96, blue: 0.63, alpha: 1)
        let heading = UILabel()
        heading.text = "OPENLENS  /  ENGO 3"
        heading.textColor = accent
        heading.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        let title = UILabel()
        title.text = "Your world, in view."
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = "Type or speak on iPhone; the result appears in your glasses."
        subtitle.textColor = .lightGray
        subtitle.numberOfLines = 0
        segment.selectedSegmentIndex = 0
        segment.selectedSegmentTintColor = accent
        segment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        field.placeholder = "Your message"
        field.backgroundColor = UIColor(white: 0.17, alpha: 1)
        field.textColor = .white
        field.layer.cornerRadius = 10
        field.heightAnchor.constraint(equalToConstant: 48).isActive = true
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.autocapitalizationType = .sentences
        send.setTitle("Show on glasses", for: .normal)
        mic.setTitle("Start listening", for: .normal)
        for button in [send, mic] {
            button.backgroundColor = accent
            button.setTitleColor(.black, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            button.layer.cornerRadius = 10
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
        send.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)
        mic.addTarget(self, action: #selector(micPressed), for: .touchUpInside)
        preview.numberOfLines = 0
        preview.textAlignment = .center
        preview.textColor = accent
        preview.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        preview.backgroundColor = UIColor(red: 0.07, green: 0.15, blue: 0.10, alpha: 1)
        preview.layer.cornerRadius = 12
        preview.layer.masksToBounds = true
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        status.text = "Connected via official ActiveLook SDK."
        status.numberOfLines = 0
        status.textColor = .lightGray
        status.font = .systemFont(ofSize: 12)
        let stack = UIStackView(arrangedSubviews: [heading, title, subtitle, segment, field, send, mic, preview, status])
        stack.axis = .vertical
        stack.spacing = 17
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        draw("OPENLENS / READY", "HELLO FROM OPENLENS")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSpeech(submit: false)
    }

    @objc private func modeChanged() {
        stopSpeech(submit: false)
        let i = segment.selectedSegmentIndex
        let labels = ["Your message", "Use iPhone microphone", "Ask AI (needs your HTTPS relay)", "Walking destination"]
        field.placeholder = labels[i]
        send.setTitle(i == 3 ? "Find next turn" : i == 2 ? "Ask AI" : "Show on glasses", for: .normal)
        mic.isHidden = i == 3
        draw("OPENLENS / " + modes[i], "READY")
    }

    // Reuses the same vendor SDK calls from GraphicsCommandsViewController.
    // Avoid Unicode in the legacy hardware font; break into short lines.
    private func draw(_ heading: String, _ message: String) {
        let normalized = message.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        let safe = normalized.unicodeScalars.map { $0.isASCII ? String($0) : " " }.joined()
        var lines = [String]()
        var current = ""
        for word in safe.split(separator: " ").map(String.init) {
            if current.count + word.count + 1 > 24 && !current.isEmpty {
                lines.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + String(word.prefix(24))
            if lines.count == 4 { break }
        }
        if !current.isEmpty && lines.count < 5 { lines.append(current) }
        glasses.clear()
        glasses.color(level: 15)
        glasses.txt(x: 8, y: 12, rotation: .bottomRL, font: 2, color: 15, string: String(heading.prefix(27)))
        glasses.line(x0: 8, x1: 290, y0: 39, y1: 39)
        for (i, line) in lines.enumerated() {
            glasses.txt(x: 8, y: 57 + i * 34, rotation: .bottomRL, font: 2, color: 15, string: line)
        }
        preview.text = heading + "\n\n" + lines.joined(separator: "\n")
        lastUpdate = Date()
        status.text = "Display commands sent. Confirm on ENGO 3 hardware."
    }

    @objc private func sendPressed() {
        view.endEditing(true)
        let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { status.text = "Enter a message first."; return }
        switch segment.selectedSegmentIndex {
        case 2: askRelay(text)
        case 3: route(to: text)
        default: draw("OPENLENS / " + modes[segment.selectedSegmentIndex], text)
        }
    }

    @objc private func micPressed() {
        if listening { stopSpeech(submit: true); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard auth == .authorized else {
                DispatchQueue.main.async { self?.status.text = "Speech recognition permission required." }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { permitted in
                DispatchQueue.main.async {
                    if permitted { self?.startSpeech() }
                    else { self?.status.text = "Microphone permission required." }
                }
            }
        }
    }

    private func startSpeech() {
        guard !listening else { return }
        guard recognizer?.isAvailable == true else {
            status.text = "Speech recognition unavailable."
            return
        }
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let node = audioEngine.inputNode
            node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
            audioEngine.prepare()
            try audioEngine.start()
            listening = true
            mic.setTitle("Stop listening", for: .normal)
            status.text = "Listening through iPhone microphone..."
            speechTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let speech = result?.bestTranscription.formattedString {
                        self.transcript = speech
                        self.field.text = speech
                        if self.segment.selectedSegmentIndex != 2 && Date().timeIntervalSince(self.lastUpdate) > 1.2 {
                            self.draw("OPENLENS / LIVE CAPTIONS", speech)
                        }
                    }
                    if error != nil { self.stopSpeech(submit: false) }
                }
            }
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            status.text = "Microphone: " + error.localizedDescription
        }
    }

    private func stopSpeech(submit: Bool) {
        guard listening else { return }
        listening = false
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        speechTask?.cancel()
        speechTask = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        mic.setTitle("Start listening", for: .normal)
        if submit && !transcript.isEmpty {
            if segment.selectedSegmentIndex == 2 { askRelay(transcript) }
            else { draw("OPENLENS / CAPTIONS", transcript) }
        }
    }

    // The app never embeds an OpenAI API key. Configure a private authenticated
    // HTTPS relay returning JSON {"text":"..."}; do not deploy it publicly unauthenticated.
    private func askRelay(_ question: String) {
        guard let raw = UserDefaults.standard.string(forKey: "openlens.relay"),
              let url = URL(string: raw), url.scheme == "https" else {
            status.text = "Set your HTTPS AI relay URL in Settings first."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["mode": "ai", "text": question])
        status.text = "Waiting for AI response..."
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if (200..<300).contains(code), let answer = json?["text"] as? String {
                    self.draw("OPENLENS / AI", answer)
                } else {
                    self.status.text = error?.localizedDescription ?? "AI relay error (HTTP \(code))."
                }
            }
        }.resume()
    }

    private func route(to destination: String) {
        guard CLLocationManager.locationServicesEnabled() else { status.text = "Location disabled."; return }
        let auth = CLLocationManager.authorizationStatus()
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            locationManager.requestWhenInUseAuthorization()
            status.text = "Allow location and tap again."
            return
        }
        guard let here = locationManager.location else {
            locationManager.requestLocation()
            status.text = "Getting location; tap again shortly."
            return
        }
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = destination
        search.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 25000, longitudinalMeters: 25000)
        MKLocalSearch(request: search).start { [weak self] response, error in
            guard let self = self else { return }
            guard let target = response?.mapItems.first else {
                self.status.text = error?.localizedDescription ?? "Destination not found."
                return
            }
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
            req.destination = target
            req.transportType = .walking
            MKDirections(request: req).calculate { result, error in
                DispatchQueue.main.async {
                    if let first = result?.routes.first?.steps.first(where: { !$0.instructions.isEmpty }) {
                        self.draw("OPENLENS / WALK", first.instructions)
                        self.status.text = "First walking turn only; not live turn-by-turn."
                    } else { self.status.text = error?.localizedDescription ?? "No walking route." }
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status.text = "Location: " + error.localizedDescription
    }

    @objc private func settings() {
        let menu = UIAlertController(title: "OpenLens Settings", message: "Choose iPhone speech language or set AI relay.", preferredStyle: .actionSheet)
        for (name, code) in [("English", "en-US"), ("Spanish", "es-ES"), ("French", "fr-FR")] {
            menu.addAction(UIAlertAction(title: "Speech: " + name, style: .default) { _ in
                self.stopSpeech(submit: false)
                self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: code))
                self.status.text = "Speech language " + name + " (transcription only)."
            })
        }
        menu.addAction(UIAlertAction(title: "Set HTTPS AI relay", style: .default) { _ in self.configureRelay() })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(menu, animated: true)
    }

    private func configureRelay() {
        let alert = UIAlertController(title: "Private AI relay", message: "Paste your HTTPS relay URL, not an API key.", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "https://example.com/openlens"
            $0.text = UserDefaults.standard.string(forKey: "openlens.relay")
            $0.autocapitalizationType = .none
            $0.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let input = alert.textFields?.first?.text ?? ""
            if !input.isEmpty && URL(string: input)?.scheme != "https" {
                self.status.text = "Use an HTTPS URL."
                return
            }
            UserDefaults.standard.set(input, forKey: "openlens.relay")
            self.status.text = input.isEmpty ? "AI relay cleared." : "AI relay saved."
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
