import AppKit
import Combine
import Foundation

enum TranscriptionViewState: Equatable {
    case idle
    case transcribing
    case completed
    case failed(String)
}

@MainActor
final class TranscriptionViewModel: ObservableObject {
    let session: TranscriptionSession
    @Published private(set) var state: TranscriptionViewState = .idle
    @Published private(set) var result: TranscriptionResult?
    @Published private(set) var warningMessages: [String] = []

    private let language: AppLanguage
    private let service: TranscriptionService

    init(
        session: TranscriptionSession,
        language: AppLanguage,
        service: TranscriptionService = TranscriptionService()
    ) {
        self.session = session
        self.language = language
        self.service = service
    }

    var transcriptText: String {
        guard let result else { return "" }
        return TranscriptFormatter.markdown(for: result, language: language)
    }

    func text(_ key: AppTextKey) -> String {
        AppLocalizer.text(key, language: language)
    }

    func start() async {
        state = .transcribing
        warningMessages = []
        do {
            let nextResult = try await service.transcribe(
                session: session,
                localeIdentifier: localeIdentifier
            )
            result = nextResult
            warningMessages = nextResult.warnings.compactMap(\.errorDescription)
            state = .completed
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
    }

    func saveTranscript() throws {
        let destination = session.outputFile
            .deletingLastPathComponent()
            .appending(path: "\(session.recordingName)-transcript.md")
        do {
            try transcriptText.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw TranscriptionError.saveFailed(error.localizedDescription)
        }
    }

    private var localeIdentifier: String {
        switch language {
        case .english: "en-US"
        case .simplifiedChinese: "zh-CN"
        }
    }
}
