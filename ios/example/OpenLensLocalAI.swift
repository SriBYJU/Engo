import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// iOS 26+ Apple Foundation Models integration. AI inference happens directly
/// on the iPhone only when the hardware, region, OS, and Apple Intelligence
/// settings permit it. No model or API key is embedded in OpenLens.
enum OpenLensOnDeviceAI {
    @MainActor
    static var isReady: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    @MainActor
    static var availabilityMessage: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple on-device AI is ready. Free and works without internet."
            case .unavailable(let reason):
                return "Apple AI is unavailable on this iPhone: \(String(describing: reason)). " +
                    "If it is still downloading, enable Apple Intelligence and try later. " +
                    "You can use a Mac running Ollama instead."
            }
        }
        #endif
        return "On-device Apple AI needs iOS 26+, a compatible iPhone, and Apple Intelligence enabled. " +
            "Choose Mac for an older iPhone."
    }

    /// Returns nil rather than faking a result when the local model is missing.
    /// The caller owns cancellation; canceled sessions cannot update the UI.
    @MainActor
    @discardableResult
    static func generate(mode: String, task: String, text: String,
                         targetLanguage: String,
                         completion: @escaping (Result<String, Error>) -> Void) -> Task<Void, Never>? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { return nil }
            let instructions = OpenLensAIPrompt.instructions(
                mode: mode, task: task, targetLanguage: targetLanguage)
            if mode == "translate" {
                let tag = ["en": "en-US", "es": "es-ES", "fr": "fr-FR",
                           "hi": "hi-IN", "te": "te-IN"][targetLanguage] ?? "en-US"
                guard SystemLanguageModel.default.supportsLocale(Locale(identifier: tag)) else {
                    completion(.failure(OpenLensOnDeviceError.unsupportedLanguage(targetLanguage)))
                    return nil
                }
            }
            return Task { @MainActor in
                do {
                    // Fresh sessions deliberately avoid storing conversation
                    // context or retaining potentially sensitive old questions.
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: text)
                    guard !Task.isCancelled else { return }
                    let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !output.isEmpty else {
                        completion(.failure(OpenLensOnDeviceError.emptyResponse))
                        return
                    }
                    completion(.success(output))
                } catch {
                    guard !Task.isCancelled else { return }
                    completion(.failure(error))
                }
            }
        }
        #endif
        return nil
    }
}

enum OpenLensOnDeviceError: LocalizedError {
    case unsupportedLanguage(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let code):
            return "Apple's on-device model may not support \(code). " +
                "Try the local Mac model for this language."
        case .emptyResponse:
            return "The on-device model returned no text. Try another prompt."
        }
    }
}
