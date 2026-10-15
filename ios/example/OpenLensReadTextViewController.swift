import UIKit
import PhotosUI
import Vision
import ActiveLookSDK

/// On-device OCR: a useful OpenLens mode that needs neither an AI server nor
/// internet. A photo/camera image is recognized locally, then sent through the
/// same tested paged-bitmap text canvas as Text and Presenter.
final class OpenLensReadTextViewController: UIViewController,
    PHPickerViewControllerDelegate, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate, UITextViewDelegate {

    private let glasses: Glasses
    private let preview = UIImageView()
    private let textView = UITextView()
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let sendButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private var recognizedText = ""
    private var requestID = 0

    init(_ glasses: Glasses) {
        self.glasses = glasses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(glasses)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Read text"
        let content = LensUI.stack(in: view)
        content.addArrangedSubview(LensUI.section("See text through ENGO 3",
            detail: "Capture a page, sign, or worksheet with your iPhone. Text recognition runs on your device; nothing is sent to an AI server."))

        preview.contentMode = .scaleAspectFit
        preview.clipsToBounds = true
        preview.backgroundColor = LensUI.card
        preview.layer.cornerRadius = 15
        preview.heightAnchor.constraint(equalToConstant: 184).isActive = true
        preview.accessibilityLabel = "Selected photo for local text recognition"
        content.addArrangedSubview(preview)

        content.addArrangedSubview(LensUI.pair(
            LensUI.tile("Take photo", subtitle: "Use camera", symbol: "camera.fill") { [weak self] in
                self?.takePhoto()
            },
            LensUI.tile("Choose image", subtitle: "Photo library", symbol: "photo.fill") { [weak self] in
                self?.chooseImage()
            }
        ))

        content.addArrangedSubview(LensUI.section("Recognized text",
            detail: "Review the result below; recognition may misread unusual fonts, handwriting, or signs."))

        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = LensUI.card
        textView.textColor = .white
        textView.layer.cornerRadius = 14
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        textView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        textView.accessibilityLabel = "Recognized text, editable for corrections"
        content.addArrangedSubview(textView)

        sendButton.configuration = .filled()
        sendButton.configuration?.title = "Show all text on glasses"
        sendButton.configuration?.image = UIImage(systemName: "eyeglasses")
        sendButton.configuration?.imagePadding = 10
        sendButton.addTarget(self, action: #selector(showOnGlasses), for: .touchUpInside)
        content.addArrangedSubview(sendButton)

        copyButton.configuration = .bordered()
        copyButton.configuration?.title = "Copy text"
        copyButton.addTarget(self, action: #selector(copyText), for: .touchUpInside)
        saveButton.configuration = .bordered()
        saveButton.configuration?.title = "Save Quick Card"
        saveButton.addTarget(self, action: #selector(saveCard), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [copyButton, saveButton])
        row.distribution = .fillEqually
        row.spacing = 10
        content.addArrangedSubview(row)

        spinner.color = LensUI.accent
        spinner.hidesWhenStopped = true
        content.addArrangedSubview(spinner)
        status.text = "Choose a photo or take one to recognize text."
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = LensUI.muted
        content.addArrangedSubview(status)
        content.addArrangedSubview(LensUI.label(
            "On-device OCR is not infallible. Double-check names, addresses and important instructions before relying on them.",
            size: 12, color: LensUI.muted))
        updateButtons()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        requestID += 1
    }

    func textViewDidChange(_ textView: UITextView) {
        // If Vision found no text, the user can still type or paste corrections.
        updateButtons()
    }

    private func updateButtons() {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText && !spinner.isAnimating
        copyButton.isEnabled = hasText && !spinner.isAnimating
        saveButton.isEnabled = hasText && !spinner.isAnimating
    }

    private func chooseImage() {
        var settings = PHPickerConfiguration(photoLibrary: .shared())
        settings.filter = .images
        settings.selectionLimit = 1
        let picker = PHPickerViewController(configuration: settings)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            status.text = "Camera is unavailable. You can still choose an existing photo."
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            status.text = "No photo selected."
            return
        }
        status.text = "Opening photo…"
        provider.loadObject(ofClass: UIImage.self) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let image = result as? UIImage else {
                    self.status.text = error?.localizedDescription ?? "Unable to load the selected photo."
                    return
                }
                self.scan(image)
            }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else {
            status.text = "Unable to use that camera photo."
            return
        }
        scan(image)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func scan(_ image: UIImage) {
        requestID += 1
        let ticket = requestID
        preview.image = image
        textView.text = ""
        recognizedText = ""
        spinner.startAnimating()
        status.text = "Reading text locally on your iPhone…"
        updateButtons()
        // Normalize and scale before invoking Vision so large phone photos do
        // not overwhelm memory and UIImage orientation is applied correctly.
        guard image.size.width > 0 && image.size.height > 0 else {
            spinner.stopAnimating()
            status.text = "Invalid image dimensions."
            updateButtons()
            return
        }
        let ratio = min(1.0, 1800 / max(image.size.width, image.size.height))
        let imageSize = CGSize(width: max(1, (image.size.width * ratio).rounded()),
                               height: max(1, (image.size.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: imageSize, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: imageSize))
            image.draw(in: CGRect(origin: .zero, size: imageSize))
        }
        guard let cg = normalized.cgImage else {
            spinner.stopAnimating()
            status.text = "Unable to process the image."
            updateButtons()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                let observations = request.results ?? []
                let text = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }.joined(separator: "\n")
                DispatchQueue.main.async {
                    guard let self = self, self.requestID == ticket else { return }
                    self.spinner.stopAnimating()
                    self.recognizedText = text
                    self.textView.text = text
                    self.updateButtons()
                    self.status.text = text.isEmpty
                        ? "No readable text found. Try a clearer, well-lit photo."
                        : "Recognized \(observations.count) text lines. You can edit mistakes before displaying them."
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, self.requestID == ticket else { return }
                    self.spinner.stopAnimating()
                    self.status.text = "Text recognition failed: \(error.localizedDescription)"
                    self.updateButtons()
                }
            }
        }
    }

    @objc private func showOnGlasses() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { status.text = "Recognize some text first."; return }
        textView.resignFirstResponder()
        let presenter = OpenLensPresenterViewController(glasses, title: "READ TEXT", body: text)
        navigationController?.pushViewController(presenter, animated: true)
    }
    @objc private func copyText() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        status.text = "Full recognized text copied."
    }
    @objc private func saveCard() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var cards = OpenLensCardLibrary.load()
        cards.insert(OpenLensCard(title: "Scanned text", body: String(text.prefix(2000))), at: 0)
        OpenLensCardLibrary.save(cards)
        status.text = "Scanned text saved in Quick Cards."
    }
}
