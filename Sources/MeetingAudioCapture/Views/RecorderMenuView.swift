import AppKit
import SwiftUI

struct RecorderMenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MeetingAudioCapture")
                        .font(.headline)
                    Text(RecordingPresentation.stateLabel(model.snapshot.state, language: model.language))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(RecordingPresentation.elapsedTime(model.snapshot.elapsedSeconds))
                    .font(.system(.body, design: .monospaced))
            }

            AudioLevelView(
                label: model.text(.systemAudio),
                level: model.snapshot.systemLevel,
                tint: .blue,
                noSignalText: model.text(.noSignal)
            )
            AudioLevelView(
                label: model.text(.microphone),
                level: model.snapshot.microphoneLevel,
                tint: .green,
                noSignalText: model.text(.noSignal)
            )

            Divider()

            Picker(model.text(.microphone), selection: $model.selectedMicrophoneID) {
                Text(model.text(.systemDefault)).tag(nil as String?)
                ForEach(model.microphones) { microphone in
                    Text(microphone.name).tag(Optional(microphone.id))
                }
            }
            .disabled(!model.canConfigure)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.text(.saveTo))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.destination.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(model.text(.choose)) { model.chooseDestination() }
                    .disabled(!model.canConfigure)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button(model.text(.openPrivacySettings)) { model.openPrivacySettings() }
            }

            HStack {
                primaryControls
                Spacer()
                if model.canOpenTranscription {
                    Button(model.text(.transcribe)) { model.openTranscriptionForLastRecording() }
                }
                if model.snapshot.outputFile != nil {
                    Button(model.text(.openFolder)) { model.revealOutputFile() }
                }
            }

            Button {
                model.selectAudioForTranscription()
            } label: {
                Label(model.text(.selectAudioAndTranscribe), systemImage: "waveform.badge.plus")
            }
            .disabled(!model.canConfigure)

            DisclosureGroup(isExpanded: $model.showsXFYunSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.xfyunConfigured {
                        Text("已配置，录音时将实时转写")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("删除讯飞凭据", role: .destructive) { model.deleteXFYunCredentials() }
                    } else {
                        TextField("讯飞 AppID", text: $model.xfyunAppIDInput)
                        SecureField("讯飞 AppKey", text: $model.xfyunAppKeyInput)
                        Button("保存到钥匙串") { model.saveXFYunCredentials() }
                            .disabled(model.xfyunAppIDInput.isEmpty || model.xfyunAppKeyInput.isEmpty)
                    }
                }
                .padding(.top, 6)
            } label: {
                Label(
                    model.xfyunConfigured ? "实时转写：已启用" : "配置讯飞实时转写",
                    systemImage: model.xfyunConfigured ? "waveform.badge.checkmark" : "key"
                )
            }
            .disabled(!model.canConfigure)

            Text(model.text(.consentNotice))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Picker(model.text(.language), selection: $model.language) {
                Text(model.text(.english)).tag(AppLanguage.english)
                Text(model.text(.simplifiedChinese)).tag(AppLanguage.simplifiedChinese)
            }
            .pickerStyle(.segmented)

            HStack {
                Button(model.text(.refreshMicrophones)) { model.refreshMicrophones() }
                    .disabled(!model.canConfigure)
                Spacer()
                Button(model.text(.quit)) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 390)
    }

    @ViewBuilder
    private var primaryControls: some View {
        switch model.snapshot.state {
        case .idle, .completed, .failed:
            Button(model.text(.startRecording)) { model.start() }
                .keyboardShortcut(.defaultAction)
        case .preparing:
            ProgressView()
                .controlSize(.small)
            Text(model.text(.waitingForTracks))
                .foregroundStyle(.secondary)
        case .recording:
            Button(model.text(.pause)) { model.pause() }
            Button(model.text(.stop)) { model.stop() }
        case .paused:
            Button(model.text(.resume)) { model.resume() }
            Button(model.text(.stop)) { model.stop() }
        case .stopping:
            ProgressView()
                .controlSize(.small)
            Text(model.text(.savingFiles))
                .foregroundStyle(.secondary)
        }
    }
}
