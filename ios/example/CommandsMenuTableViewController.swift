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
        
        title = "Advanced tools"

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
    
    // The connection is owned by OpenLensHomeViewController. Closing the
    // nested Advanced Tools menu must NOT disconnect a working ENGO 3.
    
    
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
import Security

final class OpenLensHUDViewController: UIViewController, CLLocationManagerDelegate {
    private let glasses: Glasses
    private let initialMode: Int
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var listening = false
    private var speechTapInstalled = false
    private var transcript = ""
    private var lastUpdate = Date.distantPast
    private let modes = ["TEXT", "CAPTIONS", "AI"]
    private var translationLanguage = "en"
    private let segment = UISegmentedControl(items: ["Text", "Captions", "AI"])
    private let field = UITextView()
    private let inputLabel = UILabel()
    private let fontSelector = UISegmentedControl(items: OpenLensTextSize.allCases.map(\.name))
    private let fontDetail = UILabel()
    private let pageCounter = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextPageButton = UIButton(type: .system)
    private var visiblePages: [[String]] = []
    private var currentPage = 0
    private let preview = UIImageView()
    private let pagesButton = UIButton(type: .system)
    private var fullMessage = ""
    private var fullHeading = ""
    private let status = UILabel()
    private let mic = UIButton(type: .system)
    private let send = UIButton(type: .system)
    private let relaySetup = UIButton(type: .system)
    private let relayCheck = UIButton(type: .system)
    private let relayExplanation = UILabel()
    private let providerChoice = UISegmentedControl(items: OpenLensAIProvider.allCases.map(\.title))
    private let providerNote = UILabel()
    private var onDeviceAITask: Task<Void, Never>?
    private let aiTaskButton = UIButton(type: .system)
    private let translateButton = UIButton(type: .system)
    private let fullResponse = UITextView()
    private let copyResponse = UIButton(type: .system)
    private let saveResponse = UIButton(type: .system)
    private let clearCaptions = UIButton(type: .system)
    private let copyCaptions = UIButton(type: .system)
    private let aiUtilities = UIStackView()
    private let resultUtilities = UIStackView()
    private let captionsUtilities = UIStackView()
    private var aiTask = "general"
    private var latestAIResponse = ""
    private var relayRequestID = 0
    private var relayTask: URLSessionDataTask?

    init(_ glasses: Glasses, initialMode: Int = 0) {
        self.glasses = glasses
        self.initialMode = max(0, min(2, initialMode))
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    private func setupAIUtilities() {
        aiTaskButton.configuration = .bordered()
        aiTaskButton.configuration?.title = "AI action: Answer a question ▾"
        aiTaskButton.configuration?.image = UIImage(systemName: "sparkles")
        aiTaskButton.configuration?.imagePadding = 8
        aiTaskButton.accessibilityHint = "Choose Answer, Explain, Summarize, Rewrite, or Brainstorm"
        let tasks: [(label: String, key: String)] = [
            ("Answer a question", "general"),
            ("Explain a concept", "explain"),
            ("Summarize text", "summarize"),
            ("Rewrite clearly", "rewrite"),
            ("Brainstorm ideas", "brainstorm")
        ]
        aiTaskButton.menu = UIMenu(title: "Choose an AI action", children: tasks.map { task in
            UIAction(title: task.label) { [weak self] _ in
                guard let self = self else { return }
                self.aiTask = task.key
                self.aiTaskButton.configuration?.title = "AI action: \(task.label) ▾"
                self.status.text = task.key == "general"
                    ? "Type a question, then tap Ask AI."
                    : "Enter the content or topic, then tap \(task.label)."
                self.send.setTitle(task.key == "general" ? "Ask AI" : task.label, for: .normal)
            }
        })
        aiTaskButton.showsMenuAsPrimaryAction = true

        translateButton.configuration = .bordered()
        translateButton.configuration?.title = "Translate text…"
        translateButton.configuration?.image = UIImage(systemName: "globe")
        translateButton.configuration?.imagePadding = 8
        translateButton.addTarget(self, action: #selector(translateInput), for: .touchUpInside)

        aiUtilities.axis = .vertical
        aiUtilities.spacing = 10
        aiUtilities.addArrangedSubview(aiTaskButton)
        aiUtilities.addArrangedSubview(translateButton)
        aiUtilities.isHidden = true

        fullResponse.isEditable = false
        fullResponse.isSelectable = true
        fullResponse.textColor = .white
        fullResponse.backgroundColor = UIColor(white: 0.12, alpha: 1)
        fullResponse.layer.cornerRadius = 14
        fullResponse.font = .preferredFont(forTextStyle: .body)
        fullResponse.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        fullResponse.heightAnchor.constraint(equalToConstant: 185).isActive = true
        fullResponse.accessibilityLabel = "Full AI answer"
        fullResponse.isHidden = true

        copyResponse.configuration = .bordered()
        copyResponse.configuration?.title = "Copy answer"
        copyResponse.configuration?.image = UIImage(systemName: "doc.on.doc")
        copyResponse.addTarget(self, action: #selector(copyAIAnswer), for: .touchUpInside)
        saveResponse.configuration = .bordered()
        saveResponse.configuration?.title = "Save as quick card"
        saveResponse.configuration?.image = UIImage(systemName: "bookmark")
        saveResponse.addTarget(self, action: #selector(saveAIAnswer), for: .touchUpInside)
        resultUtilities.axis = .horizontal
        resultUtilities.spacing = 10
        resultUtilities.distribution = .fillEqually
        resultUtilities.addArrangedSubview(copyResponse)
        resultUtilities.addArrangedSubview(saveResponse)
        resultUtilities.isHidden = true
    }

    private func setupCaptionUtilities() {
        clearCaptions.configuration = .bordered()
        clearCaptions.configuration?.title = "Clear captions"
        clearCaptions.addTarget(self, action: #selector(clearCaptionText), for: .touchUpInside)
        copyCaptions.configuration = .bordered()
        copyCaptions.configuration?.title = "Copy transcript"
        copyCaptions.addTarget(self, action: #selector(copyCaptionText), for: .touchUpInside)
        captionsUtilities.axis = .horizontal
        captionsUtilities.distribution = .fillEqually
        captionsUtilities.spacing = 10
        captionsUtilities.addArrangedSubview(clearCaptions)
        captionsUtilities.addArrangedSubview(copyCaptions)
        captionsUtilities.isHidden = true
    }

    @objc private func copyAIAnswer() {
        guard !latestAIResponse.isEmpty else { return }
        UIPasteboard.general.string = latestAIResponse
        status.text = "Complete answer copied to clipboard."
    }

    @objc private func saveAIAnswer() {
        guard !latestAIResponse.isEmpty else { return }
        let question = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = question.isEmpty ? "Saved AI answer" : String(question.prefix(60))
        var cards = OpenLensCardLibrary.load()
        cards.insert(OpenLensCard(title: title, body: String(latestAIResponse.prefix(2000))), at: 0)
        OpenLensCardLibrary.save(cards)
        status.text = "AI answer saved to Quick cards on this iPhone."
    }

    @objc private func clearCaptionText() {
        stopSpeech(submit: false)
        transcript = ""
        fullMessage = ""
        fullHeading = ""
        field.text = ""
        visiblePages = []
        preview.image = OpenLensCanvas.render(lines: ["CAPTIONS CLEARED"])
        pageCounter.text = "Transcript cleared"
        OpenLensCanvas.cancelPending()
        glasses.clear()
        status.text = "Captions cleared. Tap Start listening to resume."
    }

    @objc private func copyCaptionText() {
        let text = transcript.isEmpty ? field.text ?? "" : transcript
        guard !text.isEmpty else { status.text = "No captions to copy yet."; return }
        UIPasteboard.general.string = text
        status.text = "Transcript copied to clipboard."
    }

    @objc private func translateInput() {
        let text = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status.text = "Type or dictate something before translating."
            return
        }
        let options = UIAlertController(title: "Translate into", message: "Select a language to translate the entered text.", preferredStyle: .actionSheet)
        for (label, code) in [("English", "en"), ("Spanish", "es"), ("French", "fr"), ("Hindi", "hi"), ("Telugu", "te")] {
            options.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.translationLanguage = code
                self.callRelay(mode: "translate", text: text, targetLanguage: code)
            })
        }
        options.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        options.popoverPresentationController?.sourceView = translateButton
        options.popoverPresentationController?.sourceRect = translateButton.bounds
        present(options, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Text & AI"
        view.backgroundColor = UIColor(red: 0.045, green: 0.072, blue: 0.06, alpha: 1)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Options", style: .plain, target: self, action: #selector(settings))
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
        segment.selectedSegmentIndex = initialMode
        segment.selectedSegmentTintColor = accent
        segment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        inputLabel.text = "Type your message"
        inputLabel.textColor = .lightGray
        inputLabel.font = .systemFont(ofSize: 14, weight: .medium)
        field.accessibilityLabel = "Message to display"
        field.font = .systemFont(ofSize: 17)
        field.autocorrectionType = .yes
        field.textContainerInset = UIEdgeInsets(top: 14, left: 11, bottom: 14, right: 11)
        field.backgroundColor = UIColor(white: 0.17, alpha: 1)
        field.textColor = .white
        field.layer.cornerRadius = 10
        field.heightAnchor.constraint(equalToConstant: 126).isActive = true
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
        // Show the actual bitmap being sent, not an unrelated text preview.
        preview.contentMode = .scaleAspectFit
        preview.backgroundColor = .black
        preview.layer.cornerRadius = 12
        preview.layer.masksToBounds = true
        preview.heightAnchor.constraint(equalToConstant: 226).isActive = true
        preview.accessibilityLabel = "Preview of the exact text image sent to the glasses"
        status.text = "Connected via official ActiveLook SDK."
        status.numberOfLines = 0
        status.textColor = .lightGray
        status.font = .systemFont(ofSize: 12)
        fontSelector.selectedSegmentTintColor = accent
        fontSelector.selectedSegmentIndex = OpenLensTextSize.selected.rawValue
        fontSelector.addTarget(self, action: #selector(fontChanged), for: .valueChanged)
        fontDetail.textColor = .lightGray
        fontDetail.font = .systemFont(ofSize: 13)
        fontDetail.numberOfLines = 0
        updateFontDetail()

        previousButton.configuration = .filled()
        previousButton.configuration?.title = "◀ Previous"
        nextPageButton.configuration = .filled()
        nextPageButton.configuration?.title = "Next ▶"
        previousButton.addTarget(self, action: #selector(previousTextPage), for: .touchUpInside)
        nextPageButton.addTarget(self, action: #selector(nextTextPage), for: .touchUpInside)
        previousButton.isEnabled = false
        nextPageButton.isEnabled = false
        pageCounter.textColor = accent
        pageCounter.textAlignment = .center
        pageCounter.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        pageCounter.text = "Send a message to begin"
        let pager = UIStackView(arrangedSubviews: [previousButton, nextPageButton])
        pager.axis = .horizontal
        pager.distribution = .fillEqually
        pager.spacing = 12
        pagesButton.setTitle("Open in Presenter for auto-advance →", for: .normal)
        pagesButton.setTitleColor(accent, for: .normal)
        pagesButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        pagesButton.addTarget(self, action: #selector(openPages), for: .touchUpInside)
        pagesButton.isHidden = true
        providerChoice.selectedSegmentIndex = OpenLensAIProvider.selected.rawValue
        providerChoice.selectedSegmentTintColor = accent
        providerChoice.addTarget(self, action: #selector(providerChanged), for: .valueChanged)
        providerNote.textColor = .lightGray
        providerNote.font = .systemFont(ofSize: 13)
        providerNote.numberOfLines = 0
        relaySetup.configuration = .borderedProminent()
        relaySetup.configuration?.title = "Set up AI"
        relaySetup.addTarget(self, action: #selector(setupRelayPressed), for: .touchUpInside)
        relayCheck.configuration = .bordered()
        relayCheck.configuration?.title = "Test AI connection"
        relayCheck.addTarget(self, action: #selector(testRelayConnection), for: .touchUpInside)
        relayExplanation.numberOfLines = 0
        relayExplanation.textColor = .lightGray
        relayExplanation.font = .systemFont(ofSize: 13)
        relayExplanation.text = "OpenLens prefers free local AI. Cloud is optional and never used automatically."
        setupAIUtilities()
        setupCaptionUtilities()
        let sizeTitle = UILabel()
        sizeTitle.text = "TEXT SIZE ON GLASSES"
        sizeTitle.textColor = accent
        sizeTitle.font = .systemFont(ofSize: 13, weight: .bold)
        let relayRow = UIStackView(arrangedSubviews: [relaySetup, relayCheck])
        relayRow.axis = .horizontal
        relayRow.distribution = .fillEqually
        relayRow.spacing = 10
        let stack = UIStackView(arrangedSubviews: [
            heading, title, subtitle, segment, inputLabel, field,
            aiUtilities, providerChoice, providerNote, sizeTitle, fontSelector, fontDetail, send, mic,
            captionsUtilities, relayExplanation, relayRow,
            fullResponse, resultUtilities, preview, pageCounter, pager,
            pagesButton, status
        ])
        relaySetup.isHidden = true
        relayCheck.isHidden = true
        relayExplanation.isHidden = true
        providerChoice.isHidden = true
        providerNote.isHidden = true
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
        preview.image = OpenLensCanvas.render(lines: ["HELLO"], size: .selected)
        modeChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if fontSelector.selectedSegmentIndex != OpenLensTextSize.selected.rawValue {
            fontSelector.selectedSegmentIndex = OpenLensTextSize.selected.rawValue
            updateFontDetail()
            if !fullMessage.isEmpty {
                rebuildPages(startAtLatest: fullHeading.contains("CAPTIONS"))
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSpeech(submit: false)
        relayRequestID += 1
        relayTask?.cancel()
        relayTask = nil
        onDeviceAITask?.cancel()
        onDeviceAITask = nil
        send.isEnabled = true
    }

    @objc private func modeChanged() {
        stopSpeech(submit: false)
        let i = segment.selectedSegmentIndex
        let labels = ["Your message", "Use iPhone microphone", "Ask AI (needs your HTTPS relay)"]
        inputLabel.text = labels[i]
        field.accessibilityLabel = labels[i]
        send.setTitle(i == 2 ? "Ask AI" : "Show on glasses", for: .normal)
        mic.isHidden = i == 0
        aiUtilities.isHidden = i != 2
        captionsUtilities.isHidden = i != 1
        relaySetup.isHidden = i != 2
        relayCheck.isHidden = i != 2
        relayExplanation.isHidden = i != 2
        providerChoice.isHidden = i != 2
        providerNote.isHidden = i != 2
        fullResponse.isHidden = i != 2 || latestAIResponse.isEmpty
        resultUtilities.isHidden = i != 2 || latestAIResponse.isEmpty
        if i == 2 {
            let labels = ["general": "Ask AI", "explain": "Explain concept",
                          "summarize": "Summarize text", "rewrite": "Rewrite clearly",
                          "brainstorm": "Brainstorm ideas"]
            send.setTitle(labels[aiTask] ?? "Ask AI", for: .normal)
        }
        relayRequestID += 1
        relayTask?.cancel()
        relayTask = nil
        onDeviceAITask?.cancel()
        onDeviceAITask = nil
        send.isEnabled = true
        if i == 2 {
            updateAIProviderUI()
        }
        status.text = i == 1 ? "Start listening to show live captions." :
            i == 2 ? providerNote.text :
            "Type text to send to the glasses."
    }

    @objc private func providerChanged() {
        guard let selected = OpenLensAIProvider(rawValue: providerChoice.selectedSegmentIndex) else { return }
        OpenLensAIProvider.selected = selected
        relayRequestID += 1
        relayTask?.cancel()
        relayTask = nil
        onDeviceAITask?.cancel()
        onDeviceAITask = nil
        send.isEnabled = true
        updateAIProviderUI()
        status.text = providerNote.text
    }

    private func effectiveAIProvider() -> OpenLensAIProvider {
        let preference = OpenLensAIProvider.selected
        if preference == .automatic {
            return OpenLensOnDeviceAI.isReady ? .iphone : .localMac
        }
        return preference
    }

    private func updateAIProviderUI() {
        providerChoice.selectedSegmentIndex = OpenLensAIProvider.selected.rawValue
        let chosen = effectiveAIProvider()
        switch chosen {
        case .iphone:
            relaySetup.isHidden = true
            relayCheck.isHidden = false
            relayCheck.configuration?.title = "Check iPhone AI"
            providerNote.text = OpenLensOnDeviceAI.availabilityMessage
            relayExplanation.text = "Free on-device generation. No Mac, account, API key or cloud request."
        case .localMac:
            relaySetup.isHidden = false
            relayCheck.isHidden = false
            relaySetup.configuration?.title = "Pair local Mac"
            relayCheck.configuration?.title = "Test local Mac"
            let macReady = localMacURL() != nil && loadRelayToken(account: "local-mac-token") != nil
            providerNote.text = macReady
                ? "Local Mac paired. Turn on Ollama and keep your iPhone on the same trusted Wi-Fi."
                : "No on-device AI available yet. Pair free Ollama running on your MacBook Air."
            relayExplanation.text = "All model inference runs on your Mac. Mac and phone must share a trusted Wi-Fi; it is not an internet service."
        case .cloudRelay:
            relaySetup.isHidden = false
            relayCheck.isHidden = false
            relaySetup.configuration?.title = "Set up cloud relay"
            relayCheck.configuration?.title = "Test cloud relay"
            providerNote.text = "Cloud is explicitly selected; it may require paid credentials."
            relayExplanation.text = "Optional legacy Cloudflare/OpenAI relay. Automatic mode never selects cloud."
        case .automatic:
            break
        }
    }

    private func updateFontDetail() {
        let size = OpenLensTextSize.selected
        fontDetail.text = "\(size.name) • \(size.fontHeight)px high-contrast image text • \(size.charactersPerLine) chars/line • \(size.linesPerPage) lines/page"
    }

    @objc private func fontChanged() {
        guard let size = OpenLensTextSize(rawValue: fontSelector.selectedSegmentIndex) else { return }
        OpenLensTextSize.selected = size
        updateFontDetail()
        if !fullMessage.isEmpty {
            // Recompute every page for the chosen hardware font, then show page one
            // (or the latest page for streaming captions). No content is discarded.
            rebuildPages(startAtLatest: fullHeading.contains("CAPTIONS"))
        } else {
            status.text = "\(size.name) selected. Text will use \(size.fontHeight)px characters."
        }
    }

    private func draw(_ heading: String, _ message: String) {
        fullHeading = heading
        fullMessage = message
        rebuildPages(startAtLatest: heading.contains("CAPTIONS"))
        lastUpdate = Date()
    }

    private func rebuildPages(startAtLatest: Bool) {
        visiblePages = OpenLensText.pages(fullMessage, size: .selected)
        currentPage = startAtLatest ? max(0, visiblePages.count - 1) : 0
        showCurrentPage()
    }

    private func showCurrentPage() {
        guard visiblePages.indices.contains(currentPage) else { return }
        let lines = visiblePages[currentPage]
        // Include page numbers in the phone UI rather than fitting an oversized
        // header on the 304x256 glass.
        preview.image = OpenLensCanvas.show(glasses, title: fullHeading, lines: lines)
        pageCounter.text = "PAGE \(currentPage + 1) OF \(visiblePages.count)"
        previousButton.isEnabled = currentPage > 0
        nextPageButton.isEnabled = currentPage + 1 < visiblePages.count
        pagesButton.isHidden = visiblePages.count < 2
        status.text = visiblePages.count > 1
            ? "Page \(currentPage + 1)/\(visiblePages.count) queued. Use Previous / Next to see the entire message."
            : "Text queued for your glasses; confirm it is readable."
    }

    @objc private func previousTextPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        showCurrentPage()
    }

    @objc private func nextTextPage() {
        guard currentPage + 1 < visiblePages.count else { return }
        currentPage += 1
        showCurrentPage()
    }

    @objc private func openPages() {
        guard !fullMessage.isEmpty else { return }
        let controller = OpenLensPresenterViewController(glasses, title: fullHeading, body: fullMessage)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func sendPressed() {
        view.endEditing(true)
        let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { status.text = "Enter a message first."; return }
        switch segment.selectedSegmentIndex {
        case 2: askRelay(text)
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
            speechTapInstalled = true
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
                        if self.segment.selectedSegmentIndex == 1 && Date().timeIntervalSince(self.lastUpdate) > 5.0 {
                            self.draw("OPENLENS / LIVE CAPTIONS", speech)
                        }
                    }
                    if result?.isFinal == true {
                        // Recognition sessions are finite. Keep the last transcript
                        // readable rather than silently leaving the mic "listening".
                        self.stopSpeech(submit: false)
                        self.status.text = "This speech segment ended. Tap Start listening to continue."
                    } else if error != nil {
                        self.stopSpeech(submit: false)
                        self.status.text = "Speech recognition stopped: \(error?.localizedDescription ?? "unknown error"). Tap Start listening to retry."
                    }
                }
            }
        } catch {
            if audioEngine.isRunning { audioEngine.stop() }
            if speechTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                speechTapInstalled = false
            }
            req.endAudio()
            request = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            status.text = "Microphone: " + error.localizedDescription
        }
    }

    private func stopSpeech(submit: Bool) {
        guard listening else { return }
        listening = false
        if audioEngine.isRunning { audioEngine.stop() }
        if speechTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            speechTapInstalled = false
        }
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
        callRelay(mode: "ai", text: question, targetLanguage: "en")
    }

    private func relayURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: "openlens.relay")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }

    @objc private func setupRelayPressed() { configureRelay() }

    @objc private func testRelayConnection() {
        guard let endpoint = relayURL(), let token = loadRelayToken(), !token.isEmpty else {
            status.text = "Add an HTTPS relay URL and its private client token first."
            configureRelay()
            return
        }
        relayRequestID += 1
        let requestID = relayRequestID
        relayTask?.cancel()
        let url = endpoint.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        status.text = "Checking private AI relay…"
        relayTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self, self.relayRequestID == requestID else { return }
                if (200..<300).contains(code), payload?["status"] as? String == "ok" {
                    let ready = payload?["configured"] as? Bool ?? false
                    self.status.text = ready
                        ? "Relay URL is reachable and reports configured. Send a short AI question to verify the model."
                        : "Relay is online, but server AI credentials or model are missing."
                } else if code == 401 {
                    self.status.text = "Relay rejected the client token. Check the token in Set up AI."
                } else {
                    self.status.text = error?.localizedDescription ??
                        "AI health check failed (HTTP \(code)). Confirm URL and deployment."
                }
            }
        }
        relayTask?.resume()
    }

    private func callRelay(mode: String, text: String, targetLanguage: String) {
        guard let url = relayURL(), let token = loadRelayToken(), !token.isEmpty else {
            status.text = "AI is not connected. Tap Set up AI and then Test AI connection."
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status.text = "Type or dictate a question first."; return }
        guard trimmed.count <= 3000 else {
            status.text = "This is too long for the AI relay. Use up to 3,000 characters."
            return
        }
        relayRequestID += 1
        let requestID = relayRequestID
        relayTask?.cancel()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "mode": mode, "text": trimmed, "target_language": targetLanguage,
            "task": aiTask
        ])
        request.timeoutInterval = 35
        status.text = mode == "translate" ? "Translating…" : "Asking AI…"
        send.isEnabled = false
        relayTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self, self.relayRequestID == requestID else { return }
                self.send.isEnabled = true
                if (200..<300).contains(code), let raw = json?["text"] as? String,
                   !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Use the existing paged bitmap renderer to keep all answer text.
                    self.latestAIResponse = raw
                    self.fullResponse.text = raw
                    self.fullResponse.isHidden = false
                    self.resultUtilities.isHidden = false
                    self.draw(mode == "translate" ? "OPENLENS / TRANSLATE" : "OPENLENS / AI", raw)
                    self.relayExplanation.text = "Answer ready. Scroll the full response on your iPhone or use Next to read all pages on ENGO 3."
                } else {
                    let detail = (json?["error"] as? String) ?? error?.localizedDescription
                    if code == 401 {
                        self.status.text = "Invalid relay token. Open Set up AI to correct it."
                    } else if code == 429 {
                        self.status.text = "AI rate limit or quota reached. Wait and retry."
                    } else {
                        self.status.text = detail ?? "AI request failed (HTTP \(code)). Test the connection first."
                    }
                }
            }
        }
        relayTask?.resume()
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
        for (name, code) in [("English", "en-US"), ("Spanish", "es-ES"), ("French", "fr-FR"), ("Hindi", "hi-IN"), ("Telugu", "te-IN")] {
            menu.addAction(UIAlertAction(title: "Speech: " + name, style: .default) { _ in
                self.stopSpeech(submit: false)
                if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: code)) {
                    self.recognizer = recognizer
                    self.status.text = "Speech language " + name + " selected. Availability depends on iOS and the installed language."
                } else {
                    self.status.text = name + " speech recognition is not available on this iPhone."
                }
            })
        }
        menu.addAction(UIAlertAction(title: "Translate current transcript", style: .default) { _ in self.translateCurrentText() })
        menu.addAction(UIAlertAction(title: "Translation target language", style: .default) { _ in self.chooseTranslationLanguage() })
        menu.addAction(UIAlertAction(title: "Set HTTPS AI relay", style: .default) { _ in self.configureRelay() })
        menu.addAction(UIAlertAction(title: "Test AI connection", style: .default) { _ in self.testRelayConnection() })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(menu, animated: true)
    }


    // Live captions stay on-device where supported. Translation is explicitly
    // requested, and uses the user-configured HTTPS relay; it is not automatic.
    private func chooseTranslationLanguage() {
        let picker = UIAlertController(title: "Translate into", message: "Choose the output language.", preferredStyle: .actionSheet)
        for (name, code) in [("English", "en"), ("Spanish", "es"), ("French", "fr"), ("Hindi", "hi"), ("Telugu", "te")] {
            picker.addAction(UIAlertAction(title: name, style: .default) { _ in
                self.translationLanguage = code
                self.status.text = "Translation target: " + name
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        picker.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(picker, animated: true)
    }

    private func translateCurrentText() {
        let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { status.text = "Speak or type something first."; return }
        callRelay(mode: "translate", text: text, targetLanguage: translationLanguage)
    }

    private func saveRelayToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenLens-ENGO3",
            kSecAttrAccount as String: "relay-token"
        ]
        SecItemDelete(query as CFDictionary)
        if !token.isEmpty, let data = token.data(using: .utf8) {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func loadRelayToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenLens-ENGO3",
            kSecAttrAccount as String: "relay-token",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func configureRelay() {
        let alert = UIAlertController(title: "Private AI/translation relay", message: "Paste your HTTPS relay URL and its separate client token. Never paste your OpenAI API key.", preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "https://example.com/openlens"
            $0.text = UserDefaults.standard.string(forKey: "openlens.relay")
            $0.autocapitalizationType = .none
            $0.keyboardType = .URL
        }
        alert.addTextField {
            $0.placeholder = "Client token"
            $0.isSecureTextEntry = true
            $0.text = self.loadRelayToken()
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let input = alert.textFields?.first?.text ?? ""
            let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty &&
                (URL(string: cleaned)?.scheme?.lowercased() != "https" ||
                 URL(string: cleaned)?.host == nil) {
                self.status.text = "Use an HTTPS URL."
                return
            }
            UserDefaults.standard.set(cleaned, forKey: "openlens.relay")
            self.saveRelayToken(alert.textFields?.last?.text ?? "")
            self.status.text = cleaned.isEmpty
                ? "AI relay cleared."
                : "AI relay saved. Now tap Test AI connection."
            self.relayExplanation.text = cleaned.isEmpty
                ? "Set up a private relay to enable AI and translation."
                : "Relay saved. Tap Test AI connection."

        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
