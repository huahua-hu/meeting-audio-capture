import AppKit
import SwiftUI

struct RecorderMenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MeetingAudioCapture")
                        .font(.headline)
                    Text(RecordingPresentation.stateLabel(model.snapshot.state))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(RecordingPresentation.elapsedTime(model.snapshot.elapsedSeconds))
                    .font(.system(.body, design: .monospaced))
            }

            AudioLevelView(label: "System Audio", level: model.snapshot.systemLevel, tint: .blue)
            AudioLevelView(label: "Microphone", level: model.snapshot.microphoneLevel, tint: .green)

            Divider()

            Picker("Microphone", selection: $model.selectedMicrophoneID) {
                Text("System Default").tag(nil as String?)
                ForEach(model.microphones) { microphone in
                    Text(microphone.name).tag(Optional(microphone.id))
                }
            }
            .disabled(!model.canConfigure)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.destination.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Choose…") { model.chooseDestination() }
                    .disabled(!model.canConfigure)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Open Privacy Settings") { model.openPrivacySettings() }
            }

            HStack {
                primaryControls
                Spacer()
                if model.snapshot.outputDirectory != nil {
                    Button("Open Folder") { model.openOutputDirectory() }
                }
            }

            Text("Record only with required consent and in accordance with applicable laws and meeting policies.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack {
                Button("Refresh Microphones") { model.refreshMicrophones() }
                    .disabled(!model.canConfigure)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 390)
    }

    @ViewBuilder
    private var primaryControls: some View {
        switch model.snapshot.state {
        case .idle, .completed, .failed:
            Button("Start Recording") { model.start() }
                .keyboardShortcut(.defaultAction)
        case .preparing:
            ProgressView()
                .controlSize(.small)
            Text("Waiting for both audio tracks…")
                .foregroundStyle(.secondary)
        case .recording:
            Button("Pause") { model.pause() }
            Button("Stop") { model.stop() }
        case .paused:
            Button("Resume") { model.resume() }
            Button("Stop") { model.stop() }
        case .stopping:
            ProgressView()
                .controlSize(.small)
            Text("Saving files…")
                .foregroundStyle(.secondary)
        }
    }
}
