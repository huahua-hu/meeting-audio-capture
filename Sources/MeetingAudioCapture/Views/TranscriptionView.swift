import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var model: TranscriptionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            controls
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 460)
        .task {
            if model.state == .idle {
                await model.start()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.session.recordingName)
                .font(.title3)
            Text(statusText)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            Text(model.text(.transcriptionReady))
                .foregroundStyle(.secondary)
        case .transcribing:
            HStack {
                ProgressView().controlSize(.small)
                Text(model.text(.transcribing)).foregroundStyle(.secondary)
            }
            Spacer()
        case .completed:
            if !model.warningMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.text(.transcriptionWarnings)).font(.headline)
                    ForEach(Array(model.warningMessages.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            ScrollView {
                Text(model.transcriptText.isEmpty ? model.text(.noTranscript) : model.transcriptText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .failed(message):
            Text(message).foregroundStyle(.red).textSelection(.enabled)
            Spacer()
        }
    }

    private var controls: some View {
        HStack {
            Button {
                Task { await model.start() }
            } label: {
                Label(retryTitle, systemImage: "arrow.clockwise")
            }
            .disabled(model.state == .transcribing)

            Spacer()

            Button {
                model.copyTranscript()
            } label: {
                Label(model.text(.copyTranscript), systemImage: "doc.on.doc")
            }
            .disabled(model.transcriptText.isEmpty)

            Button {
                try? model.saveTranscript()
            } label: {
                Label(model.text(.saveTranscript), systemImage: "square.and.arrow.down")
            }
            .disabled(model.transcriptText.isEmpty)
        }
    }

    private var statusText: String {
        switch model.state {
        case .idle: model.text(.transcriptionReady)
        case .transcribing: model.text(.transcribing)
        case .completed: model.text(.transcription)
        case .failed: model.text(.failed)
        }
    }

    private var retryTitle: String {
        model.state == .idle ? model.text(.startTranscription) : model.text(.retryTranscription)
    }
}
