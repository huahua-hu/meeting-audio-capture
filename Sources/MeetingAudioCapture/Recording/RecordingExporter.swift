@preconcurrency import AVFoundation
import Foundation

protocol RecordingExporting: Sendable {
    func export(files: RecordingFiles) async throws -> URL
}

enum RecordingExportError: Error, LocalizedError, Sendable {
    case missingAudioTrack(String)
    case unableToCreateExporter(String)
    case exportFailed(String)
    case unableToCreateReader(String)
    case unableToCreateWriter
    case unsupportedInput(String)
    case unsupportedInputGroup
    case readerFailed(String)
    case writerFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case let .missingAudioTrack(name): "Missing \(name) audio track."
        case let .unableToCreateExporter(name): "Unable to create \(name) audio exporter."
        case let .exportFailed(name): "Unable to export \(name) audio."
        case let .unableToCreateReader(name): "Unable to create \(name) audio reader."
        case .unableToCreateWriter: "Unable to create MP4 writer."
        case let .unsupportedInput(name): "MP4 writer does not support the \(name) track."
        case .unsupportedInputGroup: "MP4 writer does not support selectable audio tracks."
        case let .readerFailed(name): "Unable to read \(name) audio."
        case let .writerFailed(details): "Unable to write MP4: \(details)"
        case let .invalidOutput(details): "Invalid MP4 output: \(details)"
        }
    }
}

struct RecordingExporter: RecordingExporting, Sendable {
    private let removeSession: @Sendable (RecordingFiles) throws -> Void

    init(
        removeSession: @escaping @Sendable (RecordingFiles) throws -> Void = {
            try $0.removeTemporarySession()
        }
    ) {
        self.removeSession = removeSession
    }

    private struct MuxSource {
        let title: String
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
    }

    func export(files: RecordingFiles) async throws -> URL {
        try await exportTrack(
            source: files.systemTemporaryCAF,
            destination: files.systemTemporaryM4A,
            name: "system"
        )
        try await exportTrack(
            source: files.microphoneTemporaryCAF,
            destination: files.microphoneTemporaryM4A,
            name: "microphone"
        )
        try await exportMix(
            system: files.systemTemporaryM4A,
            microphone: files.microphoneTemporaryM4A,
            destination: files.mixedTemporaryM4A
        )
        try await multiplex(files: files)
        try await validate(url: files.temporaryMP4)

        let outputURL = files.nextOutputURL()
        do {
            try FileManager.default.moveItem(at: files.temporaryMP4, to: outputURL)
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw RecordingExportError.exportFailed("final MP4")
        }
        try? removeSession(files)
        return outputURL
    }

    private func exportTrack(source: URL, destination: URL, name: String) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecordingExportError.unableToCreateExporter(name)
        }
        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw RecordingExportError.exportFailed(name)
        }
    }

    private func exportMix(system: URL, microphone: URL, destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let composition = AVMutableComposition()
        let systemAsset = AVURLAsset(url: system)
        let microphoneAsset = AVURLAsset(url: microphone)
        guard let systemSource = try await systemAsset.loadTracks(withMediaType: .audio).first,
              let microphoneSource = try await microphoneAsset.loadTracks(withMediaType: .audio).first,
              let systemTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ),
              let microphoneTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw RecordingExportError.missingAudioTrack("source")
        }

        let systemDuration = try await systemAsset.load(.duration)
        let microphoneDuration = try await microphoneAsset.load(.duration)
        try systemTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: systemDuration),
            of: systemSource,
            at: .zero
        )
        try microphoneTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: microphoneDuration),
            of: microphoneSource,
            at: .zero
        )

        let systemParameters = AVMutableAudioMixInputParameters(track: systemTrack)
        systemParameters.setVolume(1, at: .zero)
        let microphoneParameters = AVMutableAudioMixInputParameters(track: microphoneTrack)
        microphoneParameters.setVolume(1, at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [systemParameters, microphoneParameters]

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecordingExportError.unableToCreateExporter("mixed")
        }
        session.audioMix = audioMix
        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw RecordingExportError.exportFailed("mixed")
        }
    }

    private func multiplex(files: RecordingFiles) async throws {
        try? FileManager.default.removeItem(at: files.temporaryMP4)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: files.temporaryMP4, fileType: .mp4)
        } catch {
            throw RecordingExportError.unableToCreateWriter
        }

        let mixed = try await makeMuxSource(title: "Mixed", url: files.mixedTemporaryM4A)
        let system = try await makeMuxSource(title: "System Audio", url: files.systemTemporaryM4A)
        let microphone = try await makeMuxSource(title: "Microphone", url: files.microphoneTemporaryM4A)
        let sources = [mixed, system, microphone]

        for source in sources {
            guard writer.canAdd(source.input) else {
                throw RecordingExportError.unsupportedInput(source.title)
            }
            writer.add(source.input)
        }
        let group = AVAssetWriterInputGroup(
            inputs: sources.map(\.input),
            defaultInput: mixed.input
        )
        guard writer.canAdd(group) else {
            throw RecordingExportError.unsupportedInputGroup
        }
        writer.add(group)

        guard writer.startWriting() else {
            throw RecordingExportError.writerFailed(writer.error?.localizedDescription ?? "start failed")
        }
        writer.startSession(atSourceTime: .zero)
        for source in sources where !source.reader.startReading() {
            throw RecordingExportError.readerFailed(source.title)
        }

        var finished = Array(repeating: false, count: sources.count)
        while finished.contains(false) {
            var madeProgress = false
            for index in sources.indices where !finished[index] {
                let source = sources[index]
                guard source.input.isReadyForMoreMediaData else { continue }
                if let sample = source.output.copyNextSampleBuffer() {
                    guard source.input.append(sample) else {
                        throw RecordingExportError.writerFailed(
                            writer.error?.localizedDescription ?? "append failed"
                        )
                    }
                } else {
                    guard source.reader.status != .failed else {
                        throw RecordingExportError.readerFailed(source.title)
                    }
                    source.input.markAsFinished()
                    finished[index] = true
                }
                madeProgress = true
            }
            if writer.status == .failed {
                throw RecordingExportError.writerFailed(
                    writer.error?.localizedDescription ?? "unknown failure"
                )
            }
            if !madeProgress {
                try await Task.sleep(for: .milliseconds(2))
            }
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw RecordingExportError.writerFailed(
                writer.error?.localizedDescription ?? "finish failed"
            )
        }
    }

    private func makeMuxSource(title: String, url: URL) async throws -> MuxSource {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw RecordingExportError.missingAudioTrack(title)
        }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw RecordingExportError.unableToCreateReader(title)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw RecordingExportError.unableToCreateReader(title)
        }
        reader.add(output)

        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatHint = formatDescriptions.first else {
            throw RecordingExportError.missingAudioTrack(title)
        }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: formatHint
        )
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        input.metadata = [titleItem]
        return MuxSource(title: title, reader: reader, output: output, input: input)
    }

    private func validate(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 3 else {
            throw RecordingExportError.invalidOutput("expected three audio tracks")
        }

        var descriptions: [(title: String, enabled: Bool)] = []
        for track in tracks {
            let metadata = try await track.load(.commonMetadata)
            let titleItem = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .commonIdentifierTitle
            ).first
            guard let title = try await titleItem?.load(.stringValue) else {
                throw RecordingExportError.invalidOutput("missing track title")
            }
            descriptions.append((title, try await track.load(.isEnabled)))
        }
        guard Set(descriptions.map(\.title)) == ["Mixed", "System Audio", "Microphone"],
              descriptions.filter(\.enabled).map(\.title) == ["Mixed"] else {
            throw RecordingExportError.invalidOutput("unexpected track metadata")
        }
    }
}
