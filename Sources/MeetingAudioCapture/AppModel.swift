import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

struct MicrophoneOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor
final class AppModel: ObservableObject {
    private enum DefaultsKey {
        static let destination = "recordingDestination"
        static let microphoneID = "selectedMicrophoneID"
    }

    private let coordinator: RecordingCoordinator
    private let transcriptionWindowController = TranscriptionWindowController()
    private let credentialStore = XFYunCredentialStore()
    private var observationTask: Task<Void, Never>?
    @Published private var displayError: DisplayError?

    @Published var snapshot = RecordingSnapshot(
        state: .idle,
        elapsedSeconds: 0,
        systemLevel: .silence,
        microphoneLevel: .silence,
        outputFile: nil
    )
    @Published var microphones: [MicrophoneOption] = []
    @Published var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: DefaultsKey.microphoneID) }
    }
    @Published var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: DefaultsKey.destination) }
    }
    @Published var language: AppLanguage {
        didSet { AppLanguagePreference.save(language) }
    }
    @Published var xfyunConfigured = false
    @Published var showsXFYunSettings = false
    @Published var xfyunAppIDInput = ""
    @Published var xfyunAppKeyInput = ""

    var errorMessage: String? {
        guard let displayError else { return nil }
        switch displayError {
        case .permissionDenied:
            return text(.permissionDenied)
        case .noDisplay:
            return text(.noDisplay)
        case let .captureSetup(details):
            return AppLocalizer.format(.captureSetupFormat, language: language, details)
        case .insufficientSpace:
            return text(.insufficientSpace)
        case .exportFailed:
            return text(.exportFailed)
        case .unexpectedCaptureStop:
            return text(.unexpectedCaptureStop)
        case let .system(details):
            return AppLocalizer.format(.genericErrorFormat, language: language, details)
        }
    }

    init(coordinator: RecordingCoordinator = RecordingCoordinator(capture: ScreenCaptureClient())) {
        self.coordinator = coordinator
        try? RecordingFiles.removeStaleSessions()
        if let path = UserDefaults.standard.string(forKey: DefaultsKey.destination) {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            destination = documents.appending(path: "MeetingAudioCapture", directoryHint: .isDirectory)
        }
        selectedMicrophoneID = UserDefaults.standard.string(forKey: DefaultsKey.microphoneID)
        language = AppLanguagePreference.load()
        xfyunConfigured = (try? credentialStore.readCredentials()) != nil
        try? RecordingFiles.pruneDiagnostics(in: destination, keeping: 5)
        refreshMicrophones()
        observeSnapshots()
    }

    func text(_ key: AppTextKey) -> String {
        AppLocalizer.text(key, language: language)
    }

    var selectedMicrophoneName: String {
        microphones.first { $0.id == selectedMicrophoneID }?.name ?? "Default Microphone"
    }

    var canConfigure: Bool {
        switch snapshot.state {
        case .idle, .completed, .failed: true
        default: false
        }
    }

    var menuBarIndicator: MenuBarIndicator {
        RecordingPresentation.menuBarIndicator(snapshot.state)
    }

    var canOpenTranscription: Bool {
        guard let outputFile = snapshot.outputFile else { return false }
        return (try? TranscriptionSession.resolveSelectedAudio(outputFile: outputFile)) != nil
    }

    func refreshMicrophones() {
        microphones = AVCaptureDevice.devices(for: .audio).map {
            MicrophoneOption(id: $0.uniqueID, name: $0.localizedName)
        }
        if let selectedMicrophoneID, !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            self.selectedMicrophoneID = nil
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }

    func start() {
        displayError = nil
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            displayError = .system(error.localizedDescription)
            return
        }
        Task {
            do {
                try await coordinator.start(
                    root: destination,
                    microphoneDeviceID: selectedMicrophoneID,
                    microphoneName: selectedMicrophoneName,
                    realtimeCredentials: try? credentialStore.readCredentials()
                )
            } catch {
                displayError = displayError(for: error)
            }
        }
    }

    func saveXFYunCredentials() {
        let appID = xfyunAppIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let appKey = xfyunAppKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty, !appKey.isEmpty else { return }
        do {
            try credentialStore.saveCredentials(.init(appID: appID, appKey: appKey))
            xfyunConfigured = true
            xfyunAppIDInput = ""
            xfyunAppKeyInput = ""
            showsXFYunSettings = false
        } catch { displayError = .system(error.localizedDescription) }
    }

    func deleteXFYunCredentials() {
        do {
            try credentialStore.deleteCredentials()
            xfyunConfigured = false
        } catch { displayError = .system(error.localizedDescription) }
    }

    func pause() {
        Task {
            do { try await coordinator.pause() }
            catch { displayError = displayError(for: error) }
        }
    }

    func resume() {
        Task {
            do { try await coordinator.resume() }
            catch { displayError = displayError(for: error) }
        }
    }

    func stop() {
        Task { await coordinator.stop() }
    }

    func revealOutputFile() {
        guard let url = snapshot.outputFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openTranscriptionForLastRecording() {
        guard let outputFile = snapshot.outputFile else { return }
        do {
            let session = try TranscriptionSession.resolveSelectedAudio(outputFile: outputFile)
            transcriptionWindowController.show(session: session, language: language)
        } catch {
            displayError = .system(error.localizedDescription)
        }
    }

    func selectAudioForTranscription() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.directoryURL = destination
        panel.message = text(.selectAudioAndTranscribe)

        guard panel.runModal() == .OK, let outputFile = panel.url else { return }
        do {
            let session = try TranscriptionSession.resolveSelectedAudio(outputFile: outputFile)
            transcriptionWindowController.show(session: session, language: language)
        } catch {
            displayError = .system(error.localizedDescription)
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeSnapshots() {
        observationTask = Task {
            let stream = await coordinator.snapshots()
            for await next in stream {
                guard !Task.isCancelled else { return }
                snapshot = next
                if case let .failed(failure) = next.state {
                    displayError = displayError(forMessage: failure.message)
                }
            }
        }
    }

    private func displayError(for error: Error) -> DisplayError {
        if let captureFailure = error as? CaptureFailure {
            switch captureFailure {
            case .permissionDenied:
                return .permissionDenied
            case .noDisplayAvailable:
                return .noDisplay
            case let .setupFailed(details):
                return .captureSetup(details)
            }
        }
        if let recordingFailure = error as? RecordingFailure {
            return displayError(forMessage: recordingFailure.message)
        }
        return .system(error.localizedDescription)
    }

    private func displayError(forMessage message: String) -> DisplayError {
        switch message {
        case "At least 500 MB of free space is required.":
            return .insufficientSpace
        case "One or more audio exports failed.":
            return .exportFailed
        case "Audio capture stopped unexpectedly.":
            return .unexpectedCaptureStop
        default:
            if message.hasPrefix("Unable to start audio capture: ") {
                return .captureSetup(String(message.dropFirst("Unable to start audio capture: ".count)))
            }
            if message.contains("Recording permission was denied") {
                return .permissionDenied
            }
            return .system(message)
        }
    }

    private enum DisplayError {
        case permissionDenied
        case noDisplay
        case captureSetup(String)
        case insufficientSpace
        case exportFailed
        case unexpectedCaptureStop
        case system(String)
    }
}
