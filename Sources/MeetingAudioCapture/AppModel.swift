import AppKit
import AVFoundation
import Foundation
import Observation

struct MicrophoneOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@Observable
@MainActor
final class AppModel {
    private enum DefaultsKey {
        static let destination = "recordingDestination"
        static let microphoneID = "selectedMicrophoneID"
    }

    private let coordinator: RecordingCoordinator
    private var observationTask: Task<Void, Never>?

    var snapshot = RecordingSnapshot(
        state: .idle,
        elapsedSeconds: 0,
        systemLevel: .silence,
        microphoneLevel: .silence,
        outputDirectory: nil
    )
    var microphones: [MicrophoneOption] = []
    var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: DefaultsKey.microphoneID) }
    }
    var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: DefaultsKey.destination) }
    }
    var errorMessage: String?

    init(coordinator: RecordingCoordinator = RecordingCoordinator(capture: ScreenCaptureClient())) {
        self.coordinator = coordinator
        if let path = UserDefaults.standard.string(forKey: DefaultsKey.destination) {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            destination = documents.appending(path: "MeetingAudioCapture", directoryHint: .isDirectory)
        }
        selectedMicrophoneID = UserDefaults.standard.string(forKey: DefaultsKey.microphoneID)
        refreshMicrophones()
        observeSnapshots()
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

    var isActive: Bool {
        switch snapshot.state {
        case .preparing, .recording, .paused, .stopping: true
        default: false
        }
    }

    var menuBarIcon: String {
        switch snapshot.state {
        case .recording, .paused: "record.circle.fill"
        case .failed: "exclamationmark.triangle"
        default: "waveform"
        }
    }

    func refreshMicrophones() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        microphones = discovery.devices.map { MicrophoneOption(id: $0.uniqueID, name: $0.localizedName) }
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
        errorMessage = nil
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        Task {
            do {
                try await coordinator.start(
                    root: destination,
                    microphoneDeviceID: selectedMicrophoneID,
                    microphoneName: selectedMicrophoneName
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pause() {
        Task {
            do { try await coordinator.pause() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func resume() {
        Task {
            do { try await coordinator.resume() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func stop() {
        Task { await coordinator.stop() }
    }

    func openOutputDirectory() {
        guard let url = snapshot.outputDirectory else { return }
        NSWorkspace.shared.open(url)
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
                    errorMessage = failure.message
                }
            }
        }
    }
}
